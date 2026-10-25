#!/usr/bin/env python3
"""Relay WebSocket de matchmaking LAN para o Battle Scenes.

Execute `python tools/ws_relay.py` em uma máquina da rede local. Os jogadores
informam o IP dessa máquina e a porta 9080 no menu do jogo.
"""
from __future__ import print_function

import base64
import hashlib
import json
import socket
import struct
import sys
import threading
import uuid

GUID = b"258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
HOST = "0.0.0.0"
PORT = 9080
MAX_FRAME_BYTES = 65536
clients = {}
waiting_queue = []
rooms = {}
lock = threading.Lock()


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
    conn.sendall(encode_frame(payload))


def _clean_username(username):
    cleaned = "".join(
        character for character in str(username).strip()
        if character.isprintable()
    )
    return cleaned[:24]


def request_match(conn, username):
    username = _clean_username(username)
    if not username:
        send_json(conn, {"t": "error", "msg": "Informe um username válido."})
        return

    opponent = None
    room_id = uuid.uuid4().hex
    error_message = ""
    with lock:
        state = clients.get(conn)
        if not state:
            return
        if state["room"]:
            error_message = "Você já está em uma partida."
        elif state["queued"]:
            return
        else:
            state["username"] = username
            state["queued"] = True
            while waiting_queue:
                candidate = waiting_queue.pop(0)
                candidate_state = clients.get(candidate)
                if candidate_state and candidate_state["queued"] and candidate != conn:
                    opponent = candidate
                    break
            if opponent:
                opponent_state = clients[opponent]
                opponent_state["queued"] = False
                state["queued"] = False
                state["room"] = room_id
                state["role"] = "C"
                state["opponent"] = opponent
                opponent_state["room"] = room_id
                opponent_state["role"] = "H"
                opponent_state["opponent"] = conn
                rooms[room_id] = (opponent, conn)
                opponent_username = opponent_state["username"]
                opponent_role = opponent_state["role"]
            else:
                waiting_queue.append(conn)

    if error_message:
        send_json(conn, {"t": "error", "msg": error_message})
        return

    if not opponent:
        send_json(conn, {
            "t": "waiting",
            "msg": "Procurando partida na rede local...",
        })
        return

    send_json(opponent, {
        "t": "match_found",
        "role": opponent_role,
        "opponent": username,
    })
    send_json(conn, {
        "t": "match_found",
        "role": "C",
        "opponent": opponent_username,
    })
    print("Partida:", opponent_username, "vs", username)


def cancel_match(conn):
    with lock:
        state = clients.get(conn)
        if not state or not state["queued"]:
            return
        state["queued"] = False
        if conn in waiting_queue:
            waiting_queue.remove(conn)


def route_message(conn, data):
    kind = str(data.get("t", ""))
    if kind == "find_match":
        request_match(conn, data.get("username", ""))
        return
    if kind == "cancel_match":
        cancel_match(conn)
        return
    if kind not in ("hello", "hidden", "card"):
        return
    with lock:
        state = clients.get(conn)
        if not state or not state["room"]:
            return
        opponent = state["opponent"]
        opponent_state = clients.get(opponent)
        if not opponent_state or opponent_state["room"] != state["room"]:
            return
        room_id = state["room"]
        role = state["role"]
        username = state["username"]
    forwarded = dict(data)
    forwarded["from"] = role
    forwarded["username"] = username
    try:
        send_json(opponent, forwarded)
    except OSError:
        disconnect_client(opponent)


def disconnect_client(conn):
    opponent = None
    with lock:
        state = clients.pop(conn, None)
        if not state:
            return
        if conn in waiting_queue:
            waiting_queue.remove(conn)
        room_id = state["room"]
        if room_id:
            rooms.pop(room_id, None)
            opponent = state["opponent"]
            opponent_state = clients.get(opponent)
            if opponent_state and opponent_state["room"] == room_id:
                opponent_state["room"] = None
                opponent_state["role"] = ""
                opponent_state["opponent"] = None
    if opponent:
        try:
            send_json(opponent, {"t": "opponent_disconnected"})
        except OSError:
            pass


def handle(conn, addr):
    print("Cliente conectado:", addr)
    try:
        if not handshake(conn):
            return
        with lock:
            clients[conn] = {
                "username": "",
                "room": None,
                "role": "",
                "opponent": None,
                "queued": False,
            }
        while True:
            opcode, payload = decode_frame(conn)
            if opcode is None or opcode == 8:
                break
            if opcode == 9:
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
