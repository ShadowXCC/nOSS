#!/usr/bin/env python3
"""Tests for tools/net_sim.py: delay, loss, rate and per-client upstream sockets."""

import socket
import sys
import threading
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import net_sim  # noqa: E402


class Echo:
    """A UDP echo server that remembers who sent what."""

    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.sock.settimeout(0.05)
        self.peers = set()
        self.running = True
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    @property
    def address(self):
        return self.sock.getsockname()

    def _run(self):
        while self.running:
            try:
                data, address = self.sock.recvfrom(65536)
            except socket.timeout:
                continue
            except OSError:
                return
            self.peers.add(address)
            self.sock.sendto(data, address)

    def close(self):
        self.running = False
        self.thread.join()
        self.sock.close()


class NetSimTest(unittest.TestCase):
    def setUp(self):
        self.echo = Echo()

    def tearDown(self):
        self.echo.close()

    def _sim(self, **kw):
        sim = net_sim.NetSim(("127.0.0.1", 0), self.echo.address, seed=1, **kw)
        stop = threading.Event()

        def run():
            while not stop.is_set():
                sim.step(0.002)
        t = threading.Thread(target=run, daemon=True)
        t.start()
        self.addCleanup(lambda: (stop.set(), t.join(), sim.close()))
        return sim

    def _client(self):
        c = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        c.settimeout(2.0)
        self.addCleanup(c.close)
        return c

    def test_parse_rate(self):
        self.assertEqual(net_sim.parse_rate("50mbit"), 50e6 / 8)
        self.assertEqual(net_sim.parse_rate("6mbyte"), 6e6)
        self.assertEqual(net_sim.parse_rate("800kbit"), 100e3)
        self.assertEqual(net_sim.parse_rate("0"), 0)
        with self.assertRaises(ValueError):
            net_sim.parse_rate("fast")

    def test_round_trip_delay(self):
        sim = self._sim(delay_ms=40)
        c = self._client()
        start = time.monotonic()
        c.sendto(b"ping", ("127.0.0.1", sim.port))
        data, _ = c.recvfrom(100)
        rtt = time.monotonic() - start
        self.assertEqual(data, b"ping")
        self.assertGreaterEqual(rtt, 0.078)
        self.assertLess(rtt, 0.2)

    def test_each_client_is_its_own_peer(self):
        sim = self._sim()
        a, b = self._client(), self._client()
        for c in (a, b):
            c.sendto(b"hi", ("127.0.0.1", sim.port))
            c.recvfrom(100)
        self.assertEqual(len(self.echo.peers), 2)

    def test_loss(self):
        sim = self._sim(loss_pct=50)
        c = self._client()
        c.settimeout(0.2)
        got = 0
        for i in range(200):
            c.sendto(b"x", ("127.0.0.1", sim.port))
        try:
            while True:
                c.recvfrom(100)
                got += 1
        except socket.timeout:
            pass
        # Each way loses half: about a quarter comes back.
        self.assertGreater(got, 20)
        self.assertLess(got, 90)

    def test_rate_limit(self):
        sim = self._sim(rate=200_000, queue_ms=2000)  # 200 KB/s
        c = self._client()
        payload = b"y" * 1000
        start = time.monotonic()
        for i in range(100):  # 100 KB each way
            c.sendto(payload, ("127.0.0.1", sim.port))
        got = 0
        while got < 100:
            c.recvfrom(2000)
            got += 1
        took = time.monotonic() - start
        self.assertGreater(took, 0.4)
        self.assertLess(took, 1.5)


if __name__ == "__main__":
    unittest.main()
