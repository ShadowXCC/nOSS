#!/usr/bin/env python3
"""Tests for tools/net_check.py's pile-up grouping (the rest runs in run_tests.sh)."""

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import net_check  # noqa: E402


def c(t, a, b, x=0.0):
    return {"t": t, "a": a, "b": b, "pos": (x, 0.0, 0.0)}


class PileupTest(unittest.TestCase):
    def test_two_cars_are_not_a_pileup(self):
        self.assertEqual(net_check.pileups([c(1.0, 1, 2), c(1.2, 2, 1)]), [])

    def test_three_linked_cars_are(self):
        found = net_check.pileups([c(1.0, 1, 2), c(2.0, 2, 3)])
        self.assertEqual(len(found), 1)
        self.assertIn("3 cars", found[0])

    def test_apart_in_time_or_place(self):
        self.assertEqual(net_check.pileups([c(1.0, 1, 2), c(9.0, 2, 3)]), [])
        self.assertEqual(net_check.pileups([c(1.0, 1, 2), c(1.5, 2, 3, x=100.0)]), [])


if __name__ == "__main__":
    unittest.main()
