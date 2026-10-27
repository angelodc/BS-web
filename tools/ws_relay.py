#!/usr/bin/env python3
"""Relay WebSocket de salas LAN para o Battle Scenes.

Execute `python tools/ws_relay.py` em uma maquina da rede local. Os jogadores
informam o IP dessa maquina e a porta 9080 no menu do jogo.

O relay apenas forma salas e encaminha mensagens. A autoridade do jogo pertence
ao anfitriao (quem cria a sala), no cliente Godot.
"""
from __future__ import print_function

import base64
import hashlib
import json
import socket
import struct
import sys
import threading
import time
import uuid

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
HOST = "0.0.0.0"
PORT = 9080
# Checkpoints carry both private envelopes and public card definitions.
MAX_FRAME_BYTES = 4 * 1024 * 1024
ROOM_GRACE_SECONDS = 120
REAPER_INTERVAL_SECONDS = 5

clients = {}
waiting_queue = []
open_rooms = []
rooms = {}
resume_waiting = {}
lock = threading.Lock()
# Frames for one connection can come from its own thread and the opponent's.
send_lock = threading.Lock()

CONTROL_MESSAGES = {
    "find_match",
    "create_room",
    "cancel_match",
    "rejoin_room",
    "create_resume_room",
    "join_resume_room",
    "leave_room",
}


def recvall(conn, count):
    buf = b""
    while len(buf) < count:
        chunk = conn.recv(count - len(buf))
        if not chunk:
            return None
        buf += chunk
    return buf


def handshake(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(1024)
        if not chunk:
            return False
        data += chunk
    key = ""
    for line in data.decode("iso-8859-1", "replace").split("\r\n"):
        if line.lower().startswith("sec-websocket-key:"):
            key = line.split(":", 1)[1].strip()
    if not key:
        return False
    accept = base64.b64encode(
        hashlib.sha1(key.encode("ascii") + GUID).digest()
    ).decode("ascii")
    response = (
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: %s\r\n\r\n" % accept
    )
    conn.sendall(response.encode("ascii"))
    return True


def decode_frame(conn):
    header = recvall(conn, 2)
    if not header:
        return None, None
    opcode = header[0] & 0x0F
    masked = (header[1] & 0x80) != 0
    length = header[1] & 0x7F
    if length == 126:
        ext = recvall(conn, 2)
        if not ext:
            return None, None
        length = struct.unpack("!H", ext)[0]
    elif length == 127:
        ext = recvall(conn, 8)
        if not ext:
            return None, None
        length = struct.unpack("!Q", ext)[0]
    if length > MAX_FRAME_BYTES:
        return None, None
    mask = recvall(conn, 4) if masked else b"\x00\x00\x00\x00"
    if mask is None:
        return None, None
    payload = recvall(conn, length)
    if payload is None:
        return None, None
    if masked:
        payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return opcode, payload


def encode_frame(payload, opcode=1):
    header = bytearray([0x80 | opcode])
    length = len(payload)
    if length < 126:
        header.append(length)
    elif length < 65536:
        header.append(126)
        header.extend(struct.pack("!H", length))
    else:
        header.append(127)
        header.extend(struct.pack("!Q", length))
    return bytes(header) + payload


def send_json(conn, data):
    payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
    frame = encode_frame(payload)
    with send_lock:
        conn.sendall(frame)


def _clean_username(username):
    cleaned = "".join(
        character for character in str(username).strip()
        if character.isprintable()
    )
    return cleaned[:24]


def _clean_game_id(game_id):
    cleaned = "".join(
        character for character in str(game_id).strip()
        if character.isalnum() or character in "-_"
    )
    return cleaned[:64]


def _clean_participants(participants):
    if not isinstance(participants, list):
        return []
    cleaned = []
    for participant in participants:
        name = _clean_username(participant)
        if name and name not in cleaned:
            cleaned.append(name)
    return cleaned


def _new_client_state():
    return {
        "username": "",
        "room": None,
        "role": "",
        "opponent": None,
        "queued": False,
        "mode": "",
        "game_id": "",
        "participants": [],
        "is_host": False,
    }


def _send_error(conn, message):
    send_json(conn, {"t": "error", "msg": message})


def _send_waiting(conn, message, room_id="", mode="", game_id=""):
    payload = {"t": "waiting", "msg": message}
    if room_id:
        payload["room_id"] = room_id
    if mode:
        payload["mode"] = mode
    if game_id:
        payload["game_id"] = game_id
    send_json(conn, payload)


def _room_summary(room):
    return {
        "room_id": room["id"],
        "mode": room["mode"],
        "game_id": room["game_id"],
        "participants": list(room["participants"]),
    }


def _send_match_found(conn, role, opponent_username, room):
    payload = {
        "t": "match_found",
        "role": role,
        "opponent": opponent_username,
    }
    payload.update(_room_summary(room))
    send_json(conn, payload)


def _pair_room(room, guest):
    """Attach guest to an open room. Caller must hold the lock."""
    host = room["slots"]["H"]
    if not host or room["slots"]["C"]:
        return False
    host_state = clients.get(host)
    guest_state = clients.get(guest)
    if not host_state or not guest_state:
        return False
    host_name = host_state["username"]
    guest_name = guest_state["username"]
    if not host_name or not guest_name:
        return False
    if host_name.lower() == guest_name.lower():
        return False

    room["slots"]["C"] = guest
    room["usernames"]["C"] = guest_name
    room["vacant_since"]["C"] = None
    room["active"] = True
    if room["id"] in open_rooms:
        open_rooms.remove(room["id"])

    host_state["room"] = room["id"]
    host_state["role"] = "H"
    host_state["opponent"] = guest
    host_state["queued"] = False
    host_state["mode"] = room["mode"]
    host_state["game_id"] = room["game_id"]
    host_state["participants"] = list(room["participants"])
    host_state["is_host"] = True

    guest_state["room"] = room["id"]
    guest_state["role"] = "C"
    guest_state["opponent"] = host
    guest_state["queued"] = False
    guest_state["mode"] = room["mode"]
    guest_state["game_id"] = room["game_id"]
    guest_state["participants"] = list(room["participants"])
    guest_state["is_host"] = False

    if room["mode"] == "resume":
        resume_waiting.pop(room["game_id"], None)
        if guest in waiting_queue:
            waiting_queue.remove(guest)

    _send_match_found(host, "H", guest_name, room)
    _send_match_found(guest, "C", host_name, room)
    print("Partida:", host_name, "vs", guest_name, "sala", room["id"])
    return True


def _find_open_room_for_guest():
    for room_id in list(open_rooms):
        room = rooms.get(room_id)
        if not room:
            open_rooms.remove(room_id)
            continue
        if room["mode"] == "match" \
                and room["slots"]["H"] \
                and not room["slots"]["C"]:
            return room
    return None


def create_room(conn, username):
    username = _clean_username(username)
    if not username:
        _send_error(conn, "Informe um username valido.")
        return
    room_id = uuid.uuid4().hex
    room = {
        "id": room_id,
        "mode": "match",
        "game_id": "m_" + uuid.uuid4().hex[:16],
        "participants": [],
        "slots": {"H": conn, "C": None},
        "usernames": {"H": username, "C": ""},
        "vacant_since": {"H": None, "C": None},
        "active": False,
        "created_at": time.time(),
    }
    with lock:
        state = clients.get(conn)
        if not state:
            return
        if state["room"]:
            _send_error(conn, "Voce ja esta em uma partida.")
            return
        if state["queued"]:
            _send_error(conn, "Voce ja esta procurando uma partida.")
            return
        state["username"] = username
        state["room"] = room_id
        state["role"] = "H"
        state["opponent"] = None
        state["queued"] = True
        state["mode"] = "match"
        state["is_host"] = True
        rooms[room_id] = room
        open_rooms.append(room_id)
        guest = None
        while waiting_queue:
            candidate = waiting_queue.pop(0)
            candidate_state = clients.get(candidate)
            if candidate_state and candidate_state["queued"] \
                    and not candidate_state["room"]:
                guest = candidate
                break
        if guest:
            if _pair_room(room, guest):
                return
            candidate_state = clients.get(guest)
            if candidate_state:
                candidate_state["queued"] = False
                candidate_state["is_host"] = False
            _send_error(
                guest,
                "Use um username diferente do anfitriao para entrar.",
            )
    _send_waiting(
        conn,
        "Sala criada. Aguardando o outro jogador...",
        room_id=room_id,
        mode="match",
        game_id=room["game_id"],
    )
    print("Sala criada por", username, room_id)


def request_match(conn, username):
    """Guest searches for an open room or waits for a host to create one."""
    username = _clean_username(username)
    if not username:
        _send_error(conn, "Informe um username valido.")
        return
    with lock:
        state = clients.get(conn)
        if not state:
            return
        if state["room"]:
            _send_error(conn, "Voce ja esta em uma partida.")
            return
        if state["queued"]:
            return
        state["username"] = username
        state["queued"] = True
        state["is_host"] = False
        room = _find_open_room_for_guest()
        if room:
            if _pair_room(room, conn):
                return
            state["queued"] = False
            _send_error(
                conn,
                "Use um username diferente do anfitriao para entrar.",
            )
            return
        if conn not in waiting_queue:
            waiting_queue.append(conn)
    _send_waiting(
        conn,
        "Procurando partida na rede local...",
        mode="match",
    )


def create_resume_room(conn, game_id, username, participants):
    game_id = _clean_game_id(game_id)
    username = _clean_username(username)
    participants = _clean_participants(participants)
    if not game_id:
        _send_error(conn, "O jogo salvo nao tem um identificador valido.")
        return
    if not username:
        _send_error(conn, "Informe um username valido.")
        return
    if len(participants) != 2:
        _send_error(conn, "O jogo salvo nao identifica os dois participantes.")
        return
    if username not in participants:
        _send_error(conn, "Seu username nao participou desta partida salva.")
        return
    room_id = "resume_" + game_id
    room = {
        "id": room_id,
        "mode": "resume",
        "game_id": game_id,
        "participants": participants,
        "slots": {"H": conn, "C": None},
        "usernames": {"H": username, "C": ""},
        "vacant_since": {"H": None, "C": None},
        "active": False,
        "created_at": time.time(),
    }
    with lock:
        state = clients.get(conn)
        if not state:
            return
        if state["room"]:
            _send_error(conn, "Voce ja esta em uma partida.")
            return
        existing = rooms.get(room_id)
        if existing:
            _send_error(conn, "Ja existe uma sala de retomada para este jogo.")
            return
        state["username"] = username
        state["room"] = room_id
        state["role"] = "H"
        state["opponent"] = None
        state["queued"] = True
        state["mode"] = "resume"
        state["game_id"] = game_id
        state["participants"] = participants
        state["is_host"] = True
        rooms[room_id] = room
        waiting_guest = resume_waiting.get(game_id)
        if waiting_guest:
            guest_state = clients.get(waiting_guest)
            if guest_state and guest_state["queued"] \
                    and not guest_state["room"]:
                if guest_state["username"] not in participants:
                    guest_state["queued"] = False
                    resume_waiting.pop(game_id, None)
                    if waiting_guest in waiting_queue:
                        waiting_queue.remove(waiting_guest)
                    _send_error(
                        waiting_guest,
                        "Seu username nao participou desta partida salva.",
                    )
                else:
                    _pair_room(room, waiting_guest)
                    return
    _send_waiting(
        conn,
        "Sala de retomada criada. Aguardando o outro jogador...",
        room_id=room_id,
        mode="resume",
        game_id=game_id,
    )
    print("Retomada criada por", username, game_id)


def join_resume_room(conn, game_id, username, participants):
    game_id = _clean_game_id(game_id)
    username = _clean_username(username)
    participants = _clean_participants(participants)
    if not game_id:
        _send_error(conn, "Informe o identificador da partida salva.")
        return
    if not username:
        _send_error(conn, "Informe um username valido.")
        return
    with lock:
        state = clients.get(conn)
        if not state:
            return
        if state["room"]:
            _send_error(conn, "Voce ja esta em uma partida.")
            return
        if state["queued"]:
            return
        state["username"] = username
        state["queued"] = True
        state["is_host"] = False
        state["mode"] = "resume"
        state["game_id"] = game_id
        state["participants"] = participants
        room = rooms.get("resume_" + game_id)
        if room and room["slots"]["H"] and not room["slots"]["C"]:
            if participants and \
                    set(participants) != set(room["participants"]):
                state["queued"] = False
                _send_error(
                    conn,
                    "Os participantes deste save nao conferem com a sala.")
                return
            if username not in room["participants"]:
                state["queued"] = False
                _send_error(
                    conn,
                    "Seu username nao participou desta partida salva.")
                return
            _pair_room(room, conn)
            return
        if game_id in resume_waiting:
            state["queued"] = False
            _send_error(conn, "Ja existe um jogador esperando por esta partida.")
            return
        resume_waiting[game_id] = conn
        if conn not in waiting_queue:
            waiting_queue.append(conn)
    _send_waiting(
        conn,
        "Procurando a sala de retomada...",
        mode="resume",
        game_id=game_id,
    )


def cancel_match(conn):
    with lock:
        state = clients.get(conn)
        if not state or not state["queued"]:
            return
        room_id = state["room"]
        room = rooms.get(room_id) if room_id else None
        if room and not room["active"]:
            rooms.pop(room_id, None)
            if room_id in open_rooms:
                open_rooms.remove(room_id)
        if conn in waiting_queue:
            waiting_queue.remove(conn)
        for game_id, waiting_conn in list(resume_waiting.items()):
            if waiting_conn == conn:
                resume_waiting.pop(game_id, None)
        state["queued"] = False
        state["room"] = None
        state["role"] = ""
        state["opponent"] = None
        state["mode"] = ""
        state["game_id"] = ""
        state["participants"] = []
        state["is_host"] = False


def rejoin_room(conn, room_id, username):
    room_id = str(room_id or "")
    username = _clean_username(username)
    if not room_id or not username:
        _send_error(conn, "Nao foi possivel reconectar: dados da sala ausentes.")
        return
    with lock:
        state = clients.get(conn)
        if not state:
            return
        if state["room"]:
            _send_error(conn, "Voce ja esta em uma partida.")
            return
        room = rooms.get(room_id)
        if not room:
            send_json(conn, {
                "t": "rejoin_failed",
                "msg": "A sala nao existe mais. Use Iniciar jogo salvo.",
            })
            return
        role = ""
        for candidate_role in ("H", "C"):
            expected = room["usernames"].get(candidate_role, "")
            if expected and expected.lower() == username.lower() \
                    and room["slots"].get(candidate_role) is None:
                role = candidate_role
                break
        if not role:
            send_json(conn, {
                "t": "rejoin_failed",
                "msg": "Nao ha vaga para este username nesta sala.",
            })
            return
        room["slots"][role] = conn
        room["usernames"][role] = username
        room["vacant_since"][role] = None
        state["username"] = username
        state["room"] = room_id
        state["role"] = role
        state["queued"] = False
        state["mode"] = room["mode"]
        state["game_id"] = room["game_id"]
        state["participants"] = list(room["participants"])
        state["is_host"] = role == "H"
        opponent_role = "C" if role == "H" else "H"
        opponent = room["slots"].get(opponent_role)
        state["opponent"] = opponent
        if opponent:
            opponent_state = clients.get(opponent)
            if opponent_state:
                opponent_state["opponent"] = conn
        payload = {
            "t": "rejoin_ok",
            "room_id": room_id,
            "role": role,
            "opponent": "",
            "mode": room["mode"],
            "game_id": room["game_id"],
            "participants": list(room["participants"]),
        }
        if opponent:
            opponent_state = clients.get(opponent)
            if opponent_state:
                payload["opponent"] = opponent_state["username"]
        send_json(conn, payload)
        if opponent:
            try:
                send_json(opponent, {
                    "t": "opponent_reconnected",
                    "room_id": room_id,
                    "role": role,
                    "username": username,
                })
            except OSError:
                pass
        print("Reconectado:", username, room_id)


def route_message(conn, data):
    kind = str(data.get("t", ""))
    if kind == "create_room":
        create_room(conn, data.get("username", ""))
        return
    if kind == "find_match":
        request_match(conn, data.get("username", ""))
        return
    if kind == "cancel_match":
        cancel_match(conn)
        with lock:
            state = clients.get(conn)
            if state:
                send_json(conn, {"t": "search_cancelled"})
        return
    if kind == "rejoin_room":
        rejoin_room(
            conn,
            data.get("room_id", ""),
            data.get("username", ""),
        )
        return
    if kind == "create_resume_room":
        create_resume_room(
            conn,
            data.get("game_id", ""),
            data.get("username", ""),
            data.get("participants", []),
        )
        return
    if kind == "join_resume_room":
        join_resume_room(
            conn,
            data.get("game_id", ""),
            data.get("username", ""),
            data.get("participants", []),
        )
        return
    if kind == "leave_room":
        leave_room(conn)
        return
    if kind in CONTROL_MESSAGES:
        return
    with lock:
        state = clients.get(conn)
        if not state or not state["room"]:
            return
        opponent = state["opponent"]
        opponent_state = clients.get(opponent)
        if not opponent or not opponent_state \
                or opponent_state["room"] != state["room"]:
            return
        room_id = state["room"]
        role = state["role"]
        username = state["username"]
    forwarded = dict(data)
    forwarded["from"] = role
    forwarded["username"] = username
    forwarded["room_id"] = room_id
    try:
        send_json(opponent, forwarded)
    except OSError:
        disconnect_client(opponent)


def _clear_room_for_client(conn):
    state = clients.get(conn)
    if not state:
        return
    state["room"] = None
    state["role"] = ""
    state["opponent"] = None
    state["queued"] = False
    state["mode"] = ""
    state["game_id"] = ""
    state["participants"] = []
    state["is_host"] = False


def leave_room(conn):
    opponent = None
    with lock:
        state = clients.get(conn)
        if not state or not state["room"]:
            return
        room_id = state["room"]
        opponent = state["opponent"]
        room = rooms.pop(room_id, None)
        if room_id in open_rooms:
            open_rooms.remove(room_id)
        if room:
            for role in ("H", "C"):
                if room["game_id"]:
                    resume_waiting.pop(room["game_id"], None)
        _clear_room_for_client(conn)
        if opponent:
            opponent_state = clients.get(opponent)
            if opponent_state:
                _clear_room_for_client(opponent)
    if opponent:
        try:
            send_json(opponent, {
                "t": "opponent_left",
                "room_id": room_id if "room_id" in locals() else "",
            })
        except OSError:
            pass


def disconnect_client(conn):
    opponent = None
    notification = None
    with lock:
        state = clients.pop(conn, None)
        if not state:
            return
        if conn in waiting_queue:
            waiting_queue.remove(conn)
        for game_id, waiting_conn in list(resume_waiting.items()):
            if waiting_conn == conn:
                resume_waiting.pop(game_id, None)
        room_id = state["room"]
        if not room_id:
            return
        room = rooms.get(room_id)
        if not room:
            return
        role = state["role"]
        if not room["active"]:
            rooms.pop(room_id, None)
            if room_id in open_rooms:
                open_rooms.remove(room_id)
            if room["game_id"]:
                resume_waiting.pop(room["game_id"], None)
            return
        if room["slots"].get(role) == conn:
            room["slots"][role] = None
            room["vacant_since"][role] = time.time()
        opponent = state["opponent"]
        opponent_state = clients.get(opponent)
        if opponent and opponent_state:
            opponent_state["opponent"] = None
            opponent_state["queued"] = False
            notification = {
                "t": "opponent_disconnected",
                "room_id": room_id,
                "role": role,
                "username": state["username"],
                "mode": room["mode"],
                "game_id": room["game_id"],
                "reconnectable": True,
                "grace_seconds": ROOM_GRACE_SECONDS,
            }
    if opponent and notification:
        try:
            send_json(opponent, notification)
        except OSError:
            pass


def expire_vacant_rooms(now_value=None):
    """Drop abandoned rooms after both players have been absent.

    A room with one player still connected is kept for as long as that player
    waits, so the pair can resume after a long absence. The grace only starts
    once both slots are vacant.
    """
    now_value = time.time() if now_value is None else now_value
    with lock:
        for room_id in list(rooms.keys()):
            room = rooms[room_id]
            if not room["active"]:
                continue
            if room["slots"].get("H") is not None \
                    or room["slots"].get("C") is not None:
                continue
            vacancies = [
                room["vacant_since"].get(role)
                for role in ("H", "C")
            ]
            if any(value is None for value in vacancies):
                continue
            last_vacancy = max(vacancies)
            if now_value - last_vacancy <= ROOM_GRACE_SECONDS:
                continue
            rooms.pop(room_id, None)
            if room_id in open_rooms:
                open_rooms.remove(room_id)
            if room["game_id"]:
                resume_waiting.pop(room["game_id"], None)


def _reaper():
    while True:
        time.sleep(REAPER_INTERVAL_SECONDS)
        try:
            expire_vacant_rooms()
        except Exception as error:  # pragma: no cover - defensive thread loop
            print("Erro ao limpar salas:", error)


def handle(conn, addr):
    print("Cliente conectado:", addr)
    try:
        if not handshake(conn):
            return
        with lock:
            clients[conn] = _new_client_state()
        while True:
            opcode, payload = decode_frame(conn)
            if opcode is None or opcode == 8:
                break
            if opcode == 9:
                with send_lock:
                    conn.sendall(encode_frame(payload, 0xA))
                continue
            if opcode != 1:
                continue
            try:
                data = json.loads(payload.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                continue
            if isinstance(data, dict):
                route_message(conn, data)
    except OSError:
        pass
    finally:
        disconnect_client(conn)
        try:
            conn.close()
        except OSError:
            pass
        print("Cliente saiu:", addr)


def main():
    port = PORT
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, port))
    server.listen(8)
    reaper = threading.Thread(target=_reaper)
    reaper.daemon = True
    reaper.start()
    print("Relay LAN Battle Scenes em ws://0.0.0.0:%s" % port)
    try:
        while True:
            conn, addr = server.accept()
            thread = threading.Thread(target=handle, args=(conn, addr))
            thread.daemon = True
            thread.start()
    except KeyboardInterrupt:
        print("\nEncerrando relay.")
    finally:
        server.close()


if __name__ == "__main__":
    main()
