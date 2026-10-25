import json
import unittest

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


class RelayMatchmakingTests(unittest.TestCase):
    def setUp(self):
        with ws_relay.lock:
            ws_relay.clients.clear()
            ws_relay.waiting_queue.clear()
            ws_relay.rooms.clear()

    def add_client(self):
        connection = FakeConnection()
        with ws_relay.lock:
            ws_relay.clients[connection] = {
                "username": "",
                "room": None,
                "role": "",
                "opponent": None,
                "queued": False,
            }
        return connection

    def test_two_players_are_matched_with_names_and_distinct_roles(self):
        first = self.add_client()
        second = self.add_client()

        ws_relay.request_match(first, "Alice")
        ws_relay.request_match(second, "Bob")

        first_match = read_json_frames(first)[-1]
        second_match = read_json_frames(second)[-1]
        self.assertEqual(first_match["t"], "match_found")
        self.assertEqual(first_match["role"], "H")
        self.assertEqual(first_match["opponent"], "Bob")
        self.assertEqual(second_match["role"], "C")
        self.assertEqual(second_match["opponent"], "Alice")
        self.assertEqual(len(ws_relay.rooms), 1)

    def test_third_player_waits_outside_the_existing_match(self):
        first = self.add_client()
        second = self.add_client()
        third = self.add_client()

        ws_relay.request_match(first, "Alice")
        ws_relay.request_match(second, "Bob")
        ws_relay.request_match(third, "Carol")

        self.assertEqual(read_json_frames(third)[-1]["t"], "waiting")
        self.assertNotEqual(
            ws_relay.clients[third]["room"],
            ws_relay.clients[first]["room"],
        )

    def test_messages_are_forwarded_only_to_the_matched_opponent(self):
        first = self.add_client()
        second = self.add_client()
        waiting = self.add_client()
        ws_relay.request_match(first, "Alice")
        ws_relay.request_match(second, "Bob")
        first.frames.clear()
        second.frames.clear()
        waiting.frames.clear()

        ws_relay.route_message(first, {"t": "hidden", "msg": "Comprou carta"})

        forwarded = read_json_frames(second)[-1]
        self.assertEqual(forwarded["msg"], "Comprou carta")
        self.assertEqual(forwarded["from"], "H")
        self.assertEqual(forwarded["username"], "Alice")
        self.assertEqual(read_json_frames(waiting), [])

    def test_disconnecting_player_notifies_only_their_opponent(self):
        first = self.add_client()
        second = self.add_client()
        waiting = self.add_client()
        ws_relay.request_match(first, "Alice")
        ws_relay.request_match(second, "Bob")
        second.frames.clear()
        waiting.frames.clear()

        ws_relay.disconnect_client(first)

        self.assertEqual(
            read_json_frames(second)[-1]["t"],
            "opponent_disconnected",
        )
        self.assertIsNone(ws_relay.clients[second]["room"])
        self.assertEqual(read_json_frames(waiting), [])


if __name__ == "__main__":
    unittest.main()
