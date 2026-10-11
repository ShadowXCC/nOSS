#!/usr/bin/env python3
"""A UDP proxy that makes a link worse, for testing online play without root (no tc/netem).

Clients connect to the proxy instead of the server; each client gets its own upstream socket,
so the server still sees one peer per client. Each direction of each client's link gets:

  --delay MS     one-way delay (round trip = 2 x delay)
  --jitter MS    extra random delay, 0..MS; packets keep their order (as on most real links)
  --loss PCT     random loss, percent
  --rate RATE    bandwidth, e.g. 50mbit, 6mbyte, 800kbit (0 = unlimited); a queue longer than
                 --queue MS drops new packets (drop-tail), like a router

Example, 150 ms round trip with a little jitter and loss on a 50 Mbit line:
  tools/net_sim.py --listen 47820 --to 127.0.0.1:47800 --delay 75 --jitter 10 --loss 1 --rate 50mbit

Prints per-client totals every --stats seconds and on exit. Standard library only.
"""

import argparse
import heapq
import random
import re
import select
import signal
import socket
import sys
import time


def parse_rate(text):
    """Bytes per second from '50mbit', '6mbyte', '800kbit', '1000000' (bytes); 0 = unlimited."""
    m = re.fullmatch(r"\s*([0-9.]+)\s*([kmg]?)(bit|byte|b|)?\s*", text.lower())
    if not m:
        raise ValueError(f"bad rate: {text}")
    value = float(m.group(1)) * {"": 1, "k": 1e3, "m": 1e6, "g": 1e9}[m.group(2)]
    return value / 8.0 if m.group(3) == "bit" else value


def parse_address(text):
    host, _, port = text.rpartition(":")
    return (host or "127.0.0.1", int(port))


class Direction:
    """One way of one client's link: delay, jitter, loss and a rate-limited queue."""

    def __init__(self, sim):
        self.sim = sim
        self.busy_until = 0.0
        self.last_at = 0.0
        self.sent = 0
        self.bytes = 0
        self.dropped = 0

    def schedule(self, now, size):
        """When a packet of `size` bytes arriving now leaves the far end, or None if dropped."""
        sim = self.sim
        if sim.loss > 0.0 and sim.rng.random() < sim.loss:
            self.dropped += 1
            return None
        at = now
        if sim.rate > 0.0:
            start = max(self.busy_until, now)
            if start - now > sim.queue:
                self.dropped += 1
                return None
            self.busy_until = start + size / sim.rate
            at = self.busy_until
        self.sent += 1
        self.bytes += size
        at += sim.delay + (sim.rng.random() * sim.jitter if sim.jitter > 0.0 else 0.0)
        self.last_at = max(self.last_at, at)  # never overtakes an earlier packet
        return self.last_at


class Client:
    def __init__(self, sim, address):
        self.address = address
        self.upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.upstream.bind(("127.0.0.1" if sim.target[0].startswith("127.") else "0.0.0.0", 0))
        self.up = Direction(sim)
        self.down = Direction(sim)
        self.last = time.monotonic()


class NetSim:
    def __init__(self, listen, target, delay_ms=0.0, jitter_ms=0.0, loss_pct=0.0, rate=0.0, queue_ms=250.0, seed=None):
        self.target = target
        self.delay = delay_ms / 1000.0
        self.jitter = jitter_ms / 1000.0
        self.loss = loss_pct / 100.0
        self.rate = rate
        self.queue = queue_ms / 1000.0
        self.rng = random.Random(seed)
        self.listener = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.listener.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
        self.listener.bind(listen)
        self.listener.setblocking(False)
        self.clients = {}  # client address -> Client
        self.by_socket = {}  # upstream socket -> Client
        self.pending = []  # heap of (time, order, socket, data, address)
        self.order = 0
        self.running = True

    @property
    def port(self):
        return self.listener.getsockname()[1]

    def _client(self, address):
        c = self.clients.get(address)
        if c is None:
            c = Client(self, address)
            c.upstream.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 4 << 20)
            c.upstream.setblocking(False)
            self.clients[address] = c
            self.by_socket[c.upstream] = c
        return c

    def _queue(self, at, sock, data, address):
        if at is None:
            return
        self.order += 1
        heapq.heappush(self.pending, (at, self.order, sock, data, address))

    def step(self, timeout=0.01):
        now = time.monotonic()
        wait = timeout
        if self.pending:
            wait = max(0.0, min(timeout, self.pending[0][0] - now))
        readable, _, _ = select.select([self.listener] + list(self.by_socket), [], [], wait)
        now = time.monotonic()
        for sock in readable:
            for _ in range(512):
                try:
                    data, address = sock.recvfrom(65536)
                except (BlockingIOError, InterruptedError):
                    break
                except OSError:
                    break
                if sock is self.listener:
                    c = self._client(address)
                    c.last = now
                    self._queue(c.up.schedule(now, len(data)), c.upstream, data, self.target)
                else:
                    c = self.by_socket[sock]
                    self._queue(c.down.schedule(now, len(data)), self.listener, data, c.address)
        while self.pending and self.pending[0][0] <= now:
            _, _, sock, data, address = heapq.heappop(self.pending)
            try:
                sock.sendto(data, address)
            except BlockingIOError:
                pass  # the socket's buffer is full: like a drop
            except OSError:
                pass

    def stats(self):
        lines = []
        for address, c in self.clients.items():
            lines.append("%s:%d  up %d pkts %.1f KB lost %d  down %d pkts %.1f KB lost %d" % (
                address[0], address[1], c.up.sent, c.up.bytes / 1024, c.up.dropped,
                c.down.sent, c.down.bytes / 1024, c.down.dropped))
        return lines

    def run(self, duration=0.0, stats_every=0.0):
        start = time.monotonic()
        next_stats = start + stats_every if stats_every > 0 else None
        while self.running:
            self.step()
            now = time.monotonic()
            if duration and now - start >= duration:
                break
            if next_stats and now >= next_stats:
                next_stats = now + stats_every
                for line in self.stats():
                    print(line, flush=True)

    def close(self):
        self.listener.close()
        for c in self.clients.values():
            c.upstream.close()


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--listen", type=int, required=True, help="port clients connect to")
    p.add_argument("--to", required=True, help="server address, host:port")
    p.add_argument("--delay", type=float, default=0.0, help="one-way delay, ms")
    p.add_argument("--jitter", type=float, default=0.0, help="extra random delay, ms")
    p.add_argument("--loss", type=float, default=0.0, help="random loss, percent")
    p.add_argument("--rate", default="0", help="bandwidth each way per client, e.g. 50mbit")
    p.add_argument("--queue", type=float, default=250.0, help="longest queue before drops, ms")
    p.add_argument("--duration", type=float, default=0.0, help="stop after this many seconds")
    p.add_argument("--stats", type=float, default=0.0, help="print totals every this many seconds")
    p.add_argument("--seed", type=int, default=None)
    args = p.parse_args(argv)
    sim = NetSim(("0.0.0.0", args.listen), parse_address(args.to), args.delay, args.jitter, args.loss,
        parse_rate(args.rate), args.queue, args.seed)

    def stop(*_):
        sim.running = False
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    print("net_sim: UDP %d -> %s:%d, delay %g ms, jitter %g ms, loss %g%%, rate %s" % (
        args.listen, *parse_address(args.to), args.delay, args.jitter, args.loss, args.rate), flush=True)
    try:
        sim.run(args.duration, args.stats)
    finally:
        for line in sim.stats():
            print(line, flush=True)
        sim.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
