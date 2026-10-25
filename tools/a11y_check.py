#!/usr/bin/env python3
"""Screen-reader check (ACC-03; M4 acceptance: boot -> race -> results with a screen reader).

Runs the game with accessibility on and walks title -> Local Drive -> Race -> class -> event ->
Players -> a 1-lap race -> results -> title, then Drive Online -> Host -> the lobby -> Leave (M5), then
Local Drive -> Highway -> a highway -> its menu -> the class -> Players and back out (M7), then
Local Drive -> Kart -> a race, a battle and the cup builder -> the class -> Players and back out
(M8), then Local Drive -> Endless -> its menu -> the class -> Players and back out (M9), then the
track editor: every
tool, a new oval, its race setup and checks, a new highway loop and its ramps, the Stunts tool on
a kart circuit and an arena, and out (M6-M8);
then, in a second run, a highway session's pause menu (opened with --pause-at: keys can't be
sent on Wayland) and joining a friend from it (M7), through AT-SPI,
the interface screen readers (Orca) use: it finds controls by their accessible names, presses
them with their accessibility actions, and checks that every focusable control on each screen
has a name and that something has focus.

Runs in a private D-Bus session with the accessibility bus switched on in memory, so the
desktop's settings are left alone. Needs python3-gi with Atspi (on GNOME by default) and a
display. Writes no settings or profiles (--no-save).

    tools/a11y_check.py                # exit code 0 = pass
    tools/a11y_check.py --editor-only  # just the track editor
    tools/a11y_check.py --highway-only # just the highway menus and a highway session's pause
    tools/a11y_check.py --kart-only    # just the kart menus (race, battle, cup builder)
    tools/a11y_check.py --endless-only # just the endless menus
    tools/a11y_check.py --sumo-only    # just the Mini Games submenu and the sumo menu
    tools/a11y_check.py --drag-only    # just the Mini Games submenu and the drag menu
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
from gi.repository import Atspi, GLib  # noqa: E402

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
        try:
            a = desk.get_child_at_index(i)
            if a is not None and "godot" in (a.get_name() or "").lower():
                return a
        except GLib.GError:  # a game that has just quit
            continue
    return None


def states(node):
    try:
        return node.get_state_set()
    except Exception:
        return None


def showing(node):
    s = states(node)
    return s is not None and s.contains(Atspi.StateType.SHOWING)


def find(name, role=None, timeout=20.0, prefix=False, last=False):
    """The first showing element with this accessible name (or name prefix); the last one with
    `last` (the newest screen's: Godot shows a menu hidden behind the next one as still on screen)."""
    end = time.time() + timeout
    while time.time() < end:
        a = app()
        if a is not None:
            try:
                a.clear_cache()  # states are cached: a menu hidden since would still look showing
            except Exception:
                pass
            found = None
            for n in walk(a):
                try:
                    nm = n.get_name() or ""
                    if (nm.startswith(name) if prefix else nm == name) and showing(n) and (role is None or n.get_role_name() == role):
                        found = n
                        if not last:
                            break
                except Exception:
                    continue
            if found is not None:
                return found
        time.sleep(0.3)
    return None


def press(node, report=True):
    try:
        for i in range(node.get_n_actions()):
            if node.get_action_name(i).lower() in ("click", "press", "activate"):
                return node.do_action(i)
        return node.do_action(0)
    except Exception as e:
        if report:
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
    """Every focusable, showing control has a name; something has focus. A control freed while
    it's read (the screen still changing) means a second look."""
    for attempt in range(3):
        try:
            return _check_screen(label, settle)
        except GLib.GError:
            time.sleep(1.0)
    problems.append(f"{label}: the screen kept changing while it was read")


def _check_screen(label, settle):
    end = time.time() + settle
    while time.time() < end and focused_now() is None:  # focus is often set a frame after a screen opens
        time.sleep(0.3)
    a = app()
    if a is None:
        problems.append(f"{label}: the game isn't on the accessibility bus")
        return
    focused = None
    unnamed = []
    seen_names = []
    count = 0
    for n in walk(a):
        s = states(n)
        if s is None or not showing(n):
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
            seen_names.append(name)
            if not name.strip():
                try:
                    parent = n.get_parent()
                    where = parent.get_name() or parent.get_role_name()
                except Exception:
                    continue  # its panel is being freed (a tool rebuilding): not really there
                unnamed.append(f"{role} in '{where}'")
    if focused is None and os.environ.get("NOSS_A11Y_DEBUG"):
        for n in walk(a):
            st = states(n)
            if st is not None and st.contains(Atspi.StateType.FOCUSED):
                log(f"    focused but not showing: {n.get_role_name()} '{n.get_name()}' states {[s.value_nick for s in st.get_states()]}")
    focus_text = f"'{focused.get_name()}' ({focused.get_role_name()})" if focused is not None else "nothing"
    if focused is not None and os.environ.get("NOSS_A11Y_DEBUG"):
        chain, n = [], focused
        for _ in range(8):
            n = n.get_parent()
            if n is None:
                break
            chain.append(f"{n.get_role_name()} '{n.get_name()}'")
        log(f"    focus in: {' < '.join(chain)}")
        log("    focusable: " + ", ".join(seen_names[:30]))
    if focused is None and not any(states(n) is not None and states(n).contains(Atspi.StateType.ACTIVE)
                                   for n in walk(a) if n.get_role_name() == "frame"):
        focus_text += " (the game's window isn't active: another window has the keyboard)"
    bad_focus = focused is None or focused.get_role_name() in ("frame", "section")
    # Reported only now: a control freed while read (GLib.GError above) means a second look.
    if unnamed:
        problems.append(f"{label}: {len(unnamed)} unnamed control(s): {', '.join(sorted(set(unnamed)))}")
    if bad_focus:
        problems.append(f"{label}: focus is on {focus_text}")
    log(f"  {label}: {count} focusable controls, focus on {focus_text}")


def step(label, name, role="button", prefix=False, timeout=20.0, last=False):
    last = last or name == "Back"  # the newest screen's Back, not one hidden behind it
    node = find(name, role, timeout, prefix, last)
    if node is None:
        problems.append(f"{label}: no '{name}' {role}")
        names = sorted({f"{n.get_role_name()} '{n.get_name()}'" for n in walk(app()) if showing(n) and (n.get_name() or "")})
        log(f"  showing: {', '.join(names[:40])}")
        return False
    check_screen(label)
    # A control from the screen before can linger a moment as it's freed: look again.
    for attempt in range(3):
        try:
            shown = node.get_name()
        except Exception:
            shown = None
        if shown is not None and press(node, report=False):
            log(f"  pressed '{shown}'")
            return True
        time.sleep(1.0)
        node = find(name, role, timeout, prefix, last)
        if node is None:
            break
    problems.append(f"{label}: couldn't press '{name}'")
    return False


def highway_menus():
    """Title -> Highway -> a highway -> its menu -> its class -> Players, and back out (M7)."""
    log("Highway menus")
    ok = step("Title (highway)", "Local Drive")
    ok = ok and step("Local Drive (highway)", "Highway")
    ok = ok and step("Highway: tracks", "Lumen Ring", prefix=True)
    ok = ok and step("Highway: menu", "Next")
    ok = ok and step("Highway: class", "Highway Street", prefix=True)
    # Back out a screen at a time, each one known by something only it has.
    for label, anchor in (("Highway: players", "Ready"), ("Highway: class again", "Highway Street"),
                          ("Highway: menu again", "Next"), ("Highway: tracks again", "Lumen Ring"),
                          ("Local Drive (after highway)", "Kart")):
        ok = ok and back_from(label, anchor)
    return ok


def kart_menus():
    """Title -> Kart -> a race -> Players and back; a battle's; a cup's builder (M8)."""
    log("Kart menus")
    ok = step("Title (kart)", "Local Drive")
    ok = ok and step("Local Drive (kart)", "Kart")
    ok = ok and step("Kart: race", "Next")
    ok = ok and back_from("Kart: players", "Ready")  # each card picks its class (D149)
    ok = ok and step("Kart: to battle", "Play: Race")
    ok = ok and step("Kart: battle", "Next")
    ok = ok and back_from("Kart: battle players", "Ready")
    ok = ok and step("Kart: to cup", "Play: Battle")
    ok = ok and step("Kart: cup", "New cup")
    ok = ok and back_from("Kart: cup builder", "Save")
    ok = ok and back_from("Kart: menu", "Play: Cup")
    ok = ok and back_from("Local Drive (after kart)", "Highway")
    return ok


def endless_menus():
    """Title -> Local Drive -> Endless -> its menu -> the class -> Players, and back out (M9)."""
    log("Endless menus")
    ok = step("Title (endless)", "Local Drive")
    ok = ok and step("Local Drive (endless)", "Endless")
    ok = ok and step("Endless: menu", "Next")
    ok = ok and step("Endless: class", "Endless Cruiser", prefix=True)
    for label, anchor in (("Endless: players", "Ready"), ("Endless: class again", "Endless Cruiser"),
                          ("Endless: menu again", "Next"), ("Local Drive (after endless)", "Endless")):
        ok = ok and back_from(label, anchor)
    return ok


def sumo_menus():
    """Title -> Local Drive -> Mini Games -> Sumo Wrestling -> its menu -> Players, and back out.
    There is no class or track to pick: the mode has one class and makes its own arena (D162)."""
    log("Mini Games and sumo menus")
    ok = step("Title (sumo)", "Local Drive")
    ok = ok and step("Local Drive (sumo)", "Mini Games")
    ok = ok and step("Mini Games", "Sumo Wrestling")
    ok = ok and step("Sumo: menu", "Next")
    for label, anchor in (("Sumo: players", "Ready"), ("Sumo: menu again", "Next"),
                          ("Mini Games again", "Sumo Wrestling"), ("Local Drive (after sumo)", "Mini Games")):
        ok = ok and back_from(label, anchor)
    return ok


def drag_menus():
    """Title -> Local Drive -> Mini Games -> Drag Strip -> its menu -> Players, and back out.
    There is no class or track to pick on their own screens: the class is one of the menu's own
    rows and the strip is made from the settings (D168)."""
    log("Mini Games and drag menus")
    ok = step("Title (drag)", "Local Drive")
    ok = ok and step("Local Drive (drag)", "Mini Games")
    ok = ok and step("Mini Games (drag)", "Drag Strip")
    ok = ok and step("Drag: menu", "Next")
    for label, anchor in (("Drag: players", "Ready"), ("Drag: menu again", "Next"),
                          ("Mini Games again (drag)", "Drag Strip"), ("Local Drive (after drag)", "Mini Games")):
        ok = ok and back_from(label, anchor)
    return ok


def back_from(label, anchor):
    """Waits for the screen with `anchor` (a name prefix), checks it, and presses its Back."""
    if find(anchor, "button", timeout=30.0, prefix=True) is None:
        problems.append(f"{label}: no '{anchor}' button")
        return False
    time.sleep(1.5)  # the screen before is freed meanwhile
    return step(label, "Back", last=True)


def highway_pause_walk():
    """A highway session with two players (one autodriven), the last one's pause menu open: its
    controls, then joining the other player from it (M7)."""
    log("Highway session: pause")
    game, _ = start_game(["--highway", "--players=2", "--pause-at=12"], "noss_a11y_highway.log")
    try:
        if find("Change direction", "button", timeout=120.0) is None:
            problems.append("Highway pause: no 'Change direction' button")
            return
        step("Highway pause", "Join ", prefix=True)
        time.sleep(2.0)
        if find("Change direction", "button", timeout=2.0) is not None:
            problems.append("Highway pause: still open after joining a friend")
    finally:
        stop_game(game)


def start_game(extra, log_name):
    log_path = os.path.join(os.environ.get("TMPDIR", "/tmp"), log_name)
    log_file = open(log_path, "w")
    game = subprocess.Popen([os.path.join(ROOT, "tools/godot.sh"), "--accessibility", "always", "--"] + GAME_ARGS + extra,
                            cwd=ROOT, stdout=log_file, stderr=subprocess.STDOUT)
    log(f"Game log: {log_path}")
    return game, log_path


def stop_game(game):
    game.terminate()
    try:
        game.wait(10)
    except subprocess.TimeoutExpired:
        game.kill()


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
    # A highway (M7): its Road settings, the Ramps tool (pick a ramp), the Race tool's runs, the checks.
    step("Oval: File", "File", role="toggle button")
    step("Oval: new track", "New track")
    if find("Don't save", "button", timeout=3.0) is not None:
        step("Unsaved prompt", "Don't save")
    step("New track", "Highway loop", prefix=True)
    for tool in ["Road", "Ramps"]:
        step(f"Highway: {tool}", tool, role="toggle button")
    step("Highway: pick a ramp", "Harbour", prefix=True)
    step("Highway: ramp", "Deselect")
    for tool in ["Race", "Check"]:
        step(f"Highway: {tool}", tool, role="toggle button", prefix=(tool == "Check"))
    # Kart pieces (M8): the Stunts tool on the kart template (pick the loop) and on an arena.
    for template, piece in [("Kart circuit", "Loop"), ("Arena", None)]:
        step(f"{template}: File", "File", role="toggle button")
        step(f"{template}: new track", "New track")
        if find("Don't save", "button", timeout=3.0) is not None:
            step("Unsaved prompt", "Don't save")
        step("New track", template, prefix=True)
        step(f"{template}: Stunts", "Stunts", role="toggle button")
        if piece:
            step(f"{template}: pick a piece", piece, prefix=True)
            step(f"{template}: piece", "Deselect")
        step(f"{template}: Check", "Check", role="toggle button", prefix=True)
    step("Editor: leave", "Exit")
    if find("Don't save", "button", timeout=3.0) is not None:
        step("Unsaved prompt", "Don't save")
    if find("Local Drive", "button", timeout=20.0) is None:
        problems.append("Out of the editor: no title")


def main():
    subprocess.run(["busctl", "--user", "set-property", "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status", "IsEnabled", "b", "true"],
                   check=False, capture_output=True)
    game, _ = start_game([], "noss_a11y_check.log")
    try:
        if "--editor-only" in sys.argv:
            if find("Track Editor", "button", timeout=60.0) is not None:
                editor_walk()
            raise SystemExit(report())
        if "--highway-only" in sys.argv:
            if find("Local Drive", "button", timeout=60.0) is not None:
                highway_menus()
            stop_game(game)  # before the second run starts
            return finish()
        if "--kart-only" in sys.argv:
            if find("Local Drive", "button", timeout=60.0) is not None:
                kart_menus()
            raise SystemExit(report())
        if "--endless-only" in sys.argv:
            if find("Local Drive", "button", timeout=60.0) is not None:
                endless_menus()
            raise SystemExit(report())
        if "--sumo-only" in sys.argv:
            if find("Local Drive", "button", timeout=60.0) is not None:
                sumo_menus()
            raise SystemExit(report())
        if "--drag-only" in sys.argv:
            if find("Local Drive", "button", timeout=60.0) is not None:
                drag_menus()
            raise SystemExit(report())
        log("Title")
        ok = step("Title", "Local Drive")
        ok = ok and step("Local Drive", "Race")
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
                if find("Local Drive", "button", timeout=20.0) is None:
                    problems.append("Back at the title: no Local Drive button")
                else:
                    log("Drive Online")
                    ok = step("Title again", "Drive Online")
                    ok = ok and step("Drive Online", "Host")
                    # The Host menu is up: its rows scroll (LAN discovery is below the fold, so not
                    # showing), Start hosting doesn't. step() reports it if it never comes.
                    ok = ok and step("Host", "Start hosting")
                    if ok and find("Leave", "button", timeout=20.0) is not None:
                        find("Player 1", "button", timeout=10.0, prefix=True)  # the list arrives a tick later
                        step("Lobby", "Leave")
                        step("Drive Online again", "Back")
                    elif ok:
                        problems.append("Lobby: no Leave button")
                if find("Local Drive", "button", timeout=20.0) is not None:
                    highway_menus()
                else:
                    problems.append("Back at the title: no Local Drive button")
                if find("Local Drive", "button", timeout=20.0) is not None:
                    kart_menus()
                else:
                    problems.append("Back at the title: no Local Drive button")
                if find("Local Drive", "button", timeout=20.0) is not None:
                    endless_menus()
                else:
                    problems.append("Back at the title: no Local Drive button")
                if find("Local Drive", "button", timeout=20.0) is not None:
                    sumo_menus()
                else:
                    problems.append("Back at the title: no Local Drive button")
                if find("Local Drive", "button", timeout=20.0) is not None:
                    drag_menus()
                else:
                    problems.append("Back at the title: no Local Drive button")
                if find("Track Editor", "button", timeout=20.0) is not None:
                    editor_walk()
                else:
                    problems.append("Back at the title: no Track Editor button")
    finally:
        stop_game(game)
    return finish()


def finish():
    if not any(f in sys.argv for f in ("--editor-only", "--kart-only", "--endless-only", "--sumo-only", "--drag-only")):
        highway_pause_walk()
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
