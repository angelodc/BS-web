import json
import unittest
import unittest.mock

import ws_relay


class FakeConnection:
    def __init__(self):
        self.frames = []

    def sendall(self, data):
        self.frames.append(data)


def read_json_frames(connection):
    messages = []
    for frame in connection.frames:
        length = frame[1] & 0x7F
        offset = 2
        if length == 126:
            length = int.from_bytes(frame[offset:offset + 2], "big")
            offset += 2
        elif length == 127:
            length = int.from_bytes(frame[offset:offset + 8], "big")
            offset += 8
        messages.append(json.loads(frame[offset:offset + length].decode("utf-8")))
    return messages


def last(connection):
    return read_json_frames(connection)[-1]


class RelayMatchmakingTests(unittest.TestCase):
    def setUp(self):
        with ws_relay.lock:
            ws_relay.clients.clear()
            ws_relay.waiting_queue.clear()
            ws_relay.open_rooms.clear()
            ws_relay.rooms.clear()
            ws_relay.resume_waiting.clear()
        self._grace = ws_relay.ROOM_GRACE_SECONDS
        ws_relay.ROOM_GRACE_SECONDS = 120

    def tearDown(self):
        ws_relay.ROOM_GRACE_SECONDS = self._grace

    def add_client(self):
        connection = FakeConnection()
        with ws_relay.lock:
            ws_relay.clients[connection] = ws_relay._new_client_state()
        return connection

    def pair_players(self, host_name="Alice", guest_name="Bob"):
        host = self.add_client()
        guest = self.add_client()
        ws_relay.create_room(host, host_name)
        ws_relay.request_match(guest, guest_name)
        return host, guest

    def test_host_creates_room_then_guest_joins(self):
        host, guest = self.pair_players()

        host_match = last(host)
        guest_match = last(guest)
        self.assertEqual(host_match["t"], "match_found")
        self.assertEqual(host_match["role"], "H")
        self.assertEqual(host_match["opponent"], "Bob")
        self.assertEqual(guest_match["t"], "match_found")
        self.assertEqual(guest_match["role"], "C")
        self.assertEqual(guest_match["opponent"], "Alice")
        self.assertEqual(host_match["room_id"], guest_match["room_id"])
        self.assertEqual(len(ws_relay.rooms), 1)

    def test_guest_waits_then_host_creates_room(self):
        guest = self.add_client()
        host = self.add_client()

        ws_relay.request_match(guest, "Bob")
        self.assertEqual(last(guest)["t"], "waiting")

        ws_relay.create_room(host, "Alice")
        self.assertEqual(last(host)["t"], "match_found")
        self.assertEqual(last(guest)["t"], "match_found")
        self.assertEqual(last(host)["role"], "H")
        self.assertEqual(last(guest)["role"], "C")

    def test_third_player_waits_outside_the_existing_match(self):
        self.pair_players()
        third = self.add_client()

        ws_relay.request_match(third, "Carol")

        self.assertEqual(last(third)["t"], "waiting")
        self.assertIsNone(ws_relay.clients[third]["room"])

    def test_duplicate_usernames_cannot_join_same_room(self):
        host = self.add_client()
        guest = self.add_client()
        ws_relay.create_room(host, "Alice")
        ws_relay.request_match(guest, "Alice")

        self.assertEqual(last(guest)["t"], "error")
        self.assertEqual(last(host)["t"], "waiting")

    def test_messages_are_forwarded_only_to_the_matched_opponent(self):
        host, guest = self.pair_players()
        waiting = self.add_client()
        ws_relay.request_match(waiting, "Carol")
        host.frames.clear()
        guest.frames.clear()
        waiting.frames.clear()

        ws_relay.route_message(guest, {"t": "phase", "round": 1})
        ws_relay.route_message(host, {"t": "cursor", "x": 0.5, "y": 0.5})

        guest_received = last(host)
        host_received = last(guest)
        self.assertEqual(guest_received["t"], "phase")
        self.assertEqual(guest_received["from"], "C")
        self.assertEqual(guest_received["username"], "Bob")
        self.assertEqual(host_received["t"], "cursor")
        self.assertEqual(host_received["from"], "H")
        self.assertEqual(read_json_frames(waiting), [])

    def test_disconnecting_player_keeps_room_open_for_rejoin(self):
        host, guest = self.pair_players()
        guest.frames.clear()

        ws_relay.disconnect_client(host)

        notice = last(guest)
        self.assertEqual(notice["t"], "opponent_disconnected")
        self.assertTrue(notice["reconnectable"])
        self.assertIn(notice["room_id"], ws_relay.rooms)

        reconnected_host = self.add_client()
        ws_relay.rejoin_room(
            reconnected_host,
            notice["room_id"],
            "Alice",
        )

        self.assertEqual(last(reconnected_host)["t"], "rejoin_ok")
        self.assertEqual(last(reconnected_host)["role"], "H")
        self.assertEqual(last(guest)["t"], "opponent_reconnected")
        frames = read_json_frames(guest)
        self.assertEqual(frames[-1]["username"], "Alice")

    def test_leave_room_notifies_opponent_and_closes_room(self):
        host, guest = self.pair_players()
        guest.frames.clear()

        ws_relay.leave_room(host)

        self.assertEqual(last(guest)["t"], "opponent_left")
        self.assertIsNone(ws_relay.clients[guest]["room"])
        self.assertEqual(len(ws_relay.rooms), 0)

    def test_room_with_connected_player_is_kept_indefinitely(self):
        host, guest = self.pair_players()
        room_id = ws_relay.clients[host]["room"]
        ws_relay.disconnect_client(host)
        guest.frames.clear()
        ws_relay.ROOM_GRACE_SECONDS = 10

        ws_relay.expire_vacant_rooms(
            ws_relay.rooms[room_id]["vacant_since"]["H"] + 3600
        )

        self.assertEqual(read_json_frames(guest), [])
        self.assertEqual(ws_relay.clients[guest]["room"], room_id)
        self.assertIn(room_id, ws_relay.rooms)

    def test_room_with_both_players_absent_expires(self):
        host, guest = self.pair_players()
        room_id = ws_relay.clients[host]["room"]
        ws_relay.disconnect_client(host)
        ws_relay.disconnect_client(guest)
        ws_relay.ROOM_GRACE_SECONDS = 10
        vacancies = ws_relay.rooms[room_id]["vacant_since"]

        ws_relay.expire_vacant_rooms(max(vacancies.values()) + 11)

        self.assertNotIn(room_id, ws_relay.rooms)

    def test_resume_room_pairs_players_by_game_id(self):
        host = self.add_client()
        guest = self.add_client()
        participants = ["Alice", "Bob"]

        ws_relay.create_resume_room(host, "abc123", "Alice", participants)
        self.assertEqual(last(host)["t"], "waiting")
        ws_relay.join_resume_room(guest, "abc123", "Bob", participants)

        self.assertEqual(last(host)["t"], "match_found")
        self.assertEqual(last(guest)["t"], "match_found")
        self.assertEqual(last(host)["mode"], "resume")
        self.assertEqual(last(guest)["game_id"], "abc123")
        self.assertEqual(last(guest)["participants"], participants)

    def test_resume_with_wrong_participants_is_rejected(self):
        host = self.add_client()
        guest = self.add_client()
        ws_relay.create_resume_room(
            host, "abc123", "Alice", ["Alice", "Bob"])
        ws_relay.join_resume_room(
            guest, "abc123", "Carol", ["Alice", "Carol"])

        self.assertEqual(last(guest)["t"], "error")
        self.assertIsNone(ws_relay.clients[guest]["room"])

    def test_resume_guest_can_wait_for_host(self):
        guest = self.add_client()
        host = self.add_client()
        participants = ["Alice", "Bob"]
        ws_relay.join_resume_room(guest, "abc123", "Bob", participants)
        self.assertEqual(last(guest)["t"], "waiting")

        ws_relay.create_resume_room(host, "abc123", "Alice", participants)

        self.assertEqual(last(host)["t"], "match_found")
        self.assertEqual(last(guest)["t"], "match_found")

    def test_resume_guest_without_local_participants_joins_intact_copy(self):
        guest = self.add_client()
        host = self.add_client()

        ws_relay.join_resume_room(guest, "abc123", "Bob", [])
        self.assertEqual(last(guest)["t"], "waiting")

        ws_relay.create_resume_room(
            host, "abc123", "Alice", ["Alice", "Bob"])

        self.assertEqual(last(host)["t"], "match_found")
        self.assertEqual(last(guest)["t"], "match_found")
        self.assertEqual(last(guest)["participants"], ["Alice", "Bob"])

    def test_resume_third_party_without_local_participants_is_rejected(self):
        guest = self.add_client()
        host = self.add_client()

        ws_relay.join_resume_room(guest, "abc123", "Carol", [])
        ws_relay.create_resume_room(
            host, "abc123", "Alice", ["Alice", "Bob"])

        self.assertEqual(last(guest)["t"], "error")
        self.assertEqual(last(host)["t"], "waiting")


if __name__ == "__main__":
    unittest.main()
