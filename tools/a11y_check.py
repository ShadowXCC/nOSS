#!/usr/bin/env python3
"""Screen-reader check (ACC-03; M4 acceptance: boot -> race -> results with a screen reader).

Runs the game with accessibility on and walks title -> Race -> class -> event -> Players -> a
1-lap race -> results -> title, then Online -> Host -> the lobby -> Leave (M5), then the track
editor: every tool, a new oval, its race setup and checks, and out (M6), through AT-SPI,
the interface screen readers (Orca) use: it finds controls by their accessible names, presses
them with their accessibility actions, and checks that every focusable control on each screen
has a name and that something has focus.

Runs in a private D-Bus session with the accessibility bus switched on in memory, so the
desktop's settings are left alone. Needs python3-gi with Atspi (on GNOME by default) and a
display. Writes no settings or profiles (--no-save).

    tools/a11y_check.py                # exit code 0 = pass
    tools/a11y_check.py --editor-only  # just the track editor
"""
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# --screens=-1: P1 on the game's own window, whatever monitor this PC's players are set to (the
# walk reads focus from that window).
GAME_ARGS = ["--skip-first-boot", "--no-save", "--screen-reader", "--autodrive", "--join=1", "--race-laps=1", "--race-ai=3",
             "--race-practice=0", "--race-quali=0", "--race-grid=random", "--port=47895", "--no-upnp", "--screens=-1"]

if os.environ.get("NOSS_A11Y_PRIVATE") != "1":
    env = dict(os.environ, NOSS_A11Y_PRIVATE="1", GSETTINGS_BACKEND="memory")
    env.pop("AT_SPI_BUS_ADDRESS", None)
    sys.exit(subprocess.call(["dbus-run-session", "--", sys.executable, os.path.abspath(__file__)] + sys.argv[1:], env=env))

import warnings  # noqa: E402

warnings.simplefilter("ignore", DeprecationWarning)

import gi  # noqa: E402

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

problems = []


def log(msg):
    print(msg, flush=True)


def walk(node, depth=0):
    yield node
    if depth > 40:
        return
    try:
        for i in range(node.get_child_count()):
            child = node.get_child_at_index(i)
            if child is not None:
                yield from walk(child, depth + 1)
    except Exception:
        return


def app():
    desk = Atspi.get_desktop(0)
    for i in range(desk.get_child_count()):
        a = desk.get_child_at_index(i)
        if a is not None and "godot" in (a.get_name() or "").lower():
            return a
    return None


def states(node):
    try:
        return node.get_state_set()
    except Exception:
        return None


def showing(node):
    s = states(node)
    return s is not None and s.contains(Atspi.StateType.SHOWING)


def find(name, role=None, timeout=20.0, prefix=False):
    """The first showing element with this accessible name (or name prefix)."""
    end = time.time() + timeout
    while time.time() < end:
        a = app()
        if a is not None:
            for n in walk(a):
                try:
                    nm = n.get_name() or ""
                    if (nm.startswith(name) if prefix else nm == name) and showing(n) and (role is None or n.get_role_name() == role):
                        return n
                except Exception:
                    continue
        time.sleep(0.3)
    return None


def press(node):
    try:
        for i in range(node.get_n_actions()):
            if node.get_action_name(i).lower() in ("click", "press", "activate"):
                return node.do_action(i)
        return node.do_action(0)
    except Exception as e:
        problems.append(f"can't press '{node.get_name()}': {e}")
        return False


def focused_now():
    """The focused element, read fresh (AT-SPI caches states)."""
    a = app()
    if a is None:
        return None
    try:
        a.clear_cache()
    except Exception:
        pass
    for n in walk(a):
        st = states(n)
        if st is not None and st.contains(Atspi.StateType.FOCUSED) and n.get_role_name() not in ("frame", "section"):
            return n
    return None


def check_screen(label, settle=8.0):
    """Every focusable, showing control has a name; something has focus."""
    end = time.time() + settle
    while time.time() < end and focused_now() is None:  # focus is often set a frame after a screen opens
        time.sleep(0.3)
    a = app()
    if a is None:
        problems.append(f"{label}: the game isn't on the accessibility bus")
        return
    focused = None
    unnamed = []
    count = 0
    for n in walk(a):
        s = states(n)
        if s is None or not s.contains(Atspi.StateType.SHOWING):
            continue
        try:
            role = n.get_role_name()
        except Exception:  # gone while we looked (a panel being rebuilt)
            continue
        if s.contains(Atspi.StateType.FOCUSED):
            focused = n
        if s.contains(Atspi.StateType.FOCUSABLE) and role not in ("frame", "application", "section", "panel", "filler"):
            count += 1
            try:
                name = n.get_name() or ""
            except Exception:
                continue
            if not name.strip():
                unnamed.append(role)
    if unnamed:
        problems.append(f"{label}: {len(unnamed)} unnamed control(s): {', '.join(sorted(set(unnamed)))}")
    if focused is None and os.environ.get("NOSS_A11Y_DEBUG"):
        for n in walk(a):
            st = states(n)
            if st is not None and st.contains(Atspi.StateType.FOCUSED):
                log(f"    focused but not showing: {n.get_role_name()} '{n.get_name()}' states {[s.value_nick for s in st.get_states()]}")
    focus_text = f"'{focused.get_name()}' ({focused.get_role_name()})" if focused is not None else "nothing"
    if focused is None and not any(states(n) is not None and states(n).contains(Atspi.StateType.ACTIVE)
                                   for n in walk(a) if n.get_role_name() == "frame"):
        focus_text += " (the game's window isn't active: another window has the keyboard)"
    if focused is None or focused.get_role_name() in ("frame", "section"):
        problems.append(f"{label}: focus is on {focus_text}")
    log(f"  {label}: {count} focusable controls, focus on {focus_text}")


def step(label, name, role="button", prefix=False, timeout=20.0):
    node = find(name, role, timeout, prefix)
    if node is None:
        problems.append(f"{label}: no '{name}' {role}")
        names = sorted({f"{n.get_role_name()} '{n.get_name()}'" for n in walk(app()) if showing(n) and (n.get_name() or "")})
        log(f"  showing: {', '.join(names[:40])}")
        return False
    check_screen(label)
    press(node)
    log(f"  pressed '{node.get_name()}'")
    return True


def editor_walk():
    """The track editor (M6): each tool's panel, a new oval's race setup and checks, then out."""
    log("Track editor")
    if not step("Title (editor)", "Track Editor"):
        return
    if find("Start new", "button", timeout=3.0) is not None:  # an autosave from another run
        step("Restore prompt", "Start new")
    for tool in ["Road", "Terrain", "Paint", "Props", "Race", "Check", "File"]:  # the tool tabs toggle
        if not step(f"Editor: {tool}", tool, role="toggle button", prefix=(tool == "Check")):
            return
    step("Editor: File", "New track")
    step("New track", "Oval", prefix=True)
    for tool in ["Road", "Race", "Check"]:
        step(f"Oval: {tool}", tool, role="toggle button", prefix=(tool == "Check"))
    step("Oval: leave", "Exit")
    if find("Don't save", "button", timeout=3.0) is not None:
        step("Unsaved prompt", "Don't save")
    if find("Race", "button", timeout=20.0) is None:
        problems.append("Out of the editor: no title")


def main():
    subprocess.run(["busctl", "--user", "set-property", "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status", "IsEnabled", "b", "true"],
                   check=False, capture_output=True)
    log_path = os.path.join(os.environ.get("TMPDIR", "/tmp"), "noss_a11y_check.log")
    log_file = open(log_path, "w")
    game = subprocess.Popen([os.path.join(ROOT, "tools/godot.sh"), "--accessibility", "always", "--"] + GAME_ARGS,
                            cwd=ROOT, stdout=log_file, stderr=subprocess.STDOUT)
    log(f"Game log: {log_path}")
    try:
        if "--editor-only" in sys.argv:
            if find("Track Editor", "button", timeout=60.0) is not None:
                editor_walk()
            raise SystemExit(report())
        log("Title")
        ok = step("Title", "Race")
        ok = ok and step("Class", "Track GT", prefix=True)
        ok = ok and step("Event", "Next")
        ok = ok and step("Players", "Ready", timeout=30.0)
        if ok:
            log("Race (1 lap, autodrive)")
            row = find("P1, ", "button", timeout=240.0, prefix=True)
            if row is None:
                problems.append("Results: no result rows (the race didn't finish?)")
            else:
                rows = [n for n in walk(app()) if (n.get_name() or "").startswith("P") and ", " in (n.get_name() or "") and showing(n)]
                log(f"  {len(rows)} result rows, e.g. '{row.get_name()}'")
                step("Results", "Title")
                if find("Race", "button", timeout=20.0) is None:
                    problems.append("Back at the title: no Race button")
                else:
                    log("Online")
                    ok = step("Title again", "Online")
                    ok = ok and step("Online", "Host")
                    ok = ok and find("LAN discovery", None, timeout=20.0) is not None  # the Host menu is up
                    ok = ok and step("Host", "Start hosting")
                    if ok and find("Leave", "button", timeout=20.0) is not None:
                        find("Player 1", "button", timeout=10.0, prefix=True)  # the list arrives a tick later
                        step("Lobby", "Leave")
                        step("Online again", "Back")
                    elif ok:
                        problems.append("Lobby: no Leave button")
                if find("Track Editor", "button", timeout=20.0) is not None:
                    editor_walk()
                else:
                    problems.append("Back at the title: no Track Editor button")
    finally:
        game.terminate()
        try:
            game.wait(10)
        except subprocess.TimeoutExpired:
            game.kill()
    return report()


def report():
    if problems:
        for p in problems:
            log("FAIL " + p)
        return 1
    log("PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
