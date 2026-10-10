#!/usr/bin/env python3
"""Turns the conformance runner's CSV into a short HTML report (docs/PLATFORMS.md §5).

    python3 tools/conformance_report.py tests/conformance/out

Reads conformance.csv and summary.json from the folder and writes report.html next to them.
Exits 1 if the CSV has a failed check.
"""

import csv
import html
import json
import sys
from collections import OrderedDict
from pathlib import Path

STYLE = """
body { font: 14px/1.4 system-ui, sans-serif; margin: 24px; color: #1d1d1f; background: #fff; }
h1 { font-size: 20px; } h2 { font-size: 16px; margin-top: 28px; }
table { border-collapse: collapse; margin: 8px 0; font-variant-numeric: tabular-nums; }
th, td { border: 1px solid #ddd; padding: 3px 8px; text-align: right; white-space: nowrap; }
th:first-child, td:first-child { text-align: left; }
th { background: #f4f4f6; position: sticky; top: 0; }
td.fail { background: #fbd5d5; font-weight: 600; } td.warn { background: #fdf1cf; }
td.ref { background: #e8f0fe; } .pass { color: #186a3b; } .failed { color: #b42318; }
@media (prefers-color-scheme: dark) {
  body { background: #161618; color: #e8e8ea; } th { background: #26262a; } th, td { border-color: #3a3a40; }
  td.fail { background: #5c1f1f; } td.warn { background: #4d3f14; } td.ref { background: #1f2c45; }
  .pass { color: #7ad19b; } .failed { color: #f58f8f; }
}
"""


def main(argv):
    out = Path(argv[1] if len(argv) > 1 else "tests/conformance/out")
    if not (out / "conformance.csv").exists():
        print("No conformance.csv in %s" % out)
        return 1
    rows = list(csv.DictReader((out / "conformance.csv").open(encoding="utf-8")))
    summary = json.loads((out / "summary.json").read_text(encoding="utf-8")) if (out / "summary.json").exists() else {}
    tol = float(summary.get("tolerance_pct", 2.0))

    platforms = OrderedDict()
    for row in rows:
        platforms.setdefault(row["platform"], []).append(row)

    failed = sum(1 for r in rows if r["pass"] != "true")
    parts = [
        "<!doctype html><meta charset='utf-8'><title>nOSS conformance</title><style>%s</style>" % STYLE,
        "<h1>Platform conformance</h1>",
        "<p>Every metric within <b>±%g%%</b> of the platform's reference geometry. "
        "<span class='%s'>%s</span>: %d checks, %d failed.</p>"
        % (tol, "pass" if not failed else "failed", "PASS" if not failed else "FAIL", len(rows), failed),
    ]
    for platform, prows in platforms.items():
        metrics = []
        for r in prows:
            key = "%s.%s" % (r["maneuver"], r["metric"]) if r["metric"] else r["maneuver"]
            if key not in metrics:
                metrics.append(key)
        configs = OrderedDict()
        for r in prows:
            configs.setdefault(r["config"], {"row": r, "cells": {}})
            key = "%s.%s" % (r["maneuver"], r["metric"]) if r["metric"] else r["maneuver"]
            configs[r["config"]]["cells"][key] = r
        pfailed = sum(1 for r in prows if r["pass"] != "true")
        parts.append("<h2>%s <span class='%s'>%s</span></h2>" % (
            html.escape(platform), "pass" if not pfailed else "failed", "pass" if not pfailed else "%d failed" % pfailed))
        parts.append("<table><tr><th>config</th><th>L</th><th>T</th><th>r</th>%s<th>fit notes</th></tr>" % "".join(
            "<th>%s</th>" % html.escape(m.replace(".", "<br>", 1)).replace("&lt;br&gt;", "<br>") for m in metrics))
        for cid, c in configs.items():
            r0 = c["row"]
            cells = []
            for m in metrics:
                r = c["cells"].get(m)
                if r is None:
                    cells.append("<td></td>")
                elif r["error"]:
                    cells.append("<td class='fail' title='%s'>error</td>" % html.escape(r["error"]))
                elif cid == "ref":
                    cells.append("<td class='ref'>%s</td>" % _num(r["value"]))
                else:
                    delta = float(r["delta_pct"]) if r["delta_pct"] else 0.0
                    cls = "fail" if r["pass"] != "true" else "warn" if abs(delta) > tol / 2 else ""
                    cells.append("<td class='%s' title='%s'>%+.2f%%</td>" % (cls, _num(r["value"]), delta))
            parts.append("<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td>%s<td>%s</td></tr>" % (
                html.escape(cid), _num(r0["wheelbase"], 3), _num(r0["track"], 3), _num(r0["radius"], 3),
                "".join(cells), html.escape(r0["fit_notes"])))
        parts.append("</table>")
    (out / "report.html").write_text("\n".join(parts) + "\n", encoding="utf-8")
    print("Report: %s" % (out / "report.html"))
    return 1 if failed else 0


def _num(text, digits=4):
    try:
        return "%.*g" % (digits + 1, float(text))
    except ValueError:
        return html.escape(text) or "–"


if __name__ == "__main__":
    sys.exit(main(sys.argv))
