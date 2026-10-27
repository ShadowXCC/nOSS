#!/usr/bin/env python3
"""Screen-reader check (ACC-03; M4 acceptance: boot -> race -> results with a screen reader).

Walks the menus through AT-SPI, the interface screen readers (Orca) use: it finds controls by
their accessible names, presses them with their accessibility actions, and on each screen checks
that every focusable control has a name and that something has focus. On the way it checks that
the page under the top one isn't showing (UI overhaul P2: only the top page shows). The routes,
in the order the full walk runs them (docs/UI_FLOW.md §12):

  race      Local Drive -> Racing -> Regular -> its Settings -> the class -> Players -> a 1-lap
            race -> the results: Event menu (that Settings page again) and back out, then Drive
            again -> Players and back out a page at a time (M4; P4)
  racing    Stock Car (no Class step) to Players; the Time Trial switch: Regular's and Kart's
            time trials to Players; Custom and its Save preset page (P4-P6)
  online    Drive Online -> Host -> the event pages (a time trial's Minutes too) -> the class,
            which hosts -> the lobby: Change event, Playlist, This PC's rows, Driving Settings ->
            Leave; Join's tabs, Official off (M5; P8-P10)
  highway   Highway -> its Settings -> the class -> Players and back out (M7; P5)
  kart      Kart's race, cup and cup builder; Mini Games -> Kart Battle -> Players (M8; P5)
  endless   Endless -> its Settings -> the class -> Players (M9; P5)
  sumo      Mini Games -> Sumo Wrestling -> its Settings -> Players (P5)
  drag      Mini Games -> Drag Strip -> its Settings -> the class -> Players (P5)
  free      Free Drive -> its Settings -> the class -> Players (P5)
  settings  Settings: every tab, Reset to defaults and Clear downloads asking first (Keep),
            Profiles; Driving Settings: every tab, Comfort's reset asking first (P3, P11)
  garage    the Garage's tabs, a car's page and its Drive's class page, the Fitting Bay's Import
            step ("From online games"), Exit back to the Garage (P7, P7b, P11)
  editor    the track editor: every tool, a new oval, a highway loop and its ramps, the Stunts
            tool on a kart circuit and an arena (M6-M8)
Then each in a game of its own:
  pause      a highway session with two players, the last one's pause menu (--pause-at: keys
             can't be sent on Wayland): its Driving Settings and back, then joining the other
             player from it (M7, P11)
  first boot the first-boot Accessibility screen: its Driving Settings and back, then Done to
             the main menu (ACC-09, P11)

Runs in a private D-Bus session with the accessibility bus switched on in memory, so the
desktop's settings are left alone. Needs python3-gi with Atspi (on GNOME by default; the system
python3, not the venv) and a display that's awake. Writes no settings or profiles (--no-save).

    tools/a11y_check.py                    # every route; exit code 0 = pass
    tools/a11y_check.py --<route>-only     # one route (several flags: those), e.g. --garage-only;
                                           # --highway-only adds the pause run
    tools/a11y_check.py --first-boot-only  # just the first-boot screen
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


def find(name, role=None, timeout=20.0, prefix=False, last=False, contains=False):
    """The first showing element with this accessible name (or name prefix, or with `contains` a
    name that has it anywhere); the last one with `last` (the newest screen's, should one under it
    still show)."""
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
                    matched = name in nm if contains else nm.startswith(name) if prefix else nm == name
                    if matched and showing(n) and (role is None or n.get_role_name() == role):
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
    try:
        a.clear_cache()  # states are cached: the focus may have moved since the wait above
    except Exception:
        pass
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
    if focused is None:  # the focus moved while the screen was read (a tab switching): once more, fresh
        n = focused_now()
        if n is not None and showing(n):
            focused = n
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


def step(label, name, role="button", prefix=False, timeout=20.0, last=False, contains=False):
    last = last or name == "Back"  # the newest screen's Back, not one hidden behind it
    node = find(name, role, timeout, prefix, last, contains)
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
        node = find(name, role, timeout, prefix, last, contains)
        if node is None:
            break
    problems.append(f"{label}: couldn't press '{name}'")
    return False


def highway_menus():
    """Main menu -> Local Drive -> Highway -> its Settings page -> the class -> Players, and back
    out a page at a time (M7, UI overhaul P5)."""
    log("Highway pages")
    ok = step("Main menu (highway)", "Local Drive")
    ok = ok and step("Local Drive (highway)", "Highway")
    ok = ok and hidden("Highway: settings", "Mini Games")
    ok = ok and step("Highway: settings", "Next")
    ok = ok and step("Highway: class", "Highway Street", prefix=True)
    # Back out a page at a time, each one known by something only it has.
    for label, anchor in (("Highway: players", "Ready"), ("Highway: class again", "Highway Street"),
                          ("Highway: settings again", "Mode: "), ("Local Drive (after highway)", "Racing")):
        ok = ok and back_from(label, anchor)
    return ok


def kart_menus():
    """Main menu -> Racing -> Kart -> a race -> Players and back; a cup and its builder; then Mini
    Games -> Kart Battle -> Players, and back out (M8, UI overhaul P5)."""
    log("Kart pages")
    ok = step("Main menu (kart)", "Local Drive")
    ok = ok and step("Local Drive (kart)", "Racing")
    ok = ok and step("Racing (kart)", "Kart")
    if ok and find("Play: Cup", "button", timeout=5.0) is not None:  # a cup set up last time
        ok = step("Kart: to race", "Play: Cup")
    ok = ok and step("Kart: race", "Next")
    ok = ok and back_from("Kart: players", "Ready")  # each card picks its class (D149)
    ok = ok and step("Kart: to cup", "Play: Race")
    ok = ok and step("Kart: cup", "New cup")
    ok = ok and back_from("Kart: cup builder", "Race 1 laps")
    ok = ok and back_from("Kart: settings", "Play: Cup")
    ok = ok and back_from("Racing (after kart)", "Custom")
    ok = ok and step("Local Drive (battle)", "Mini Games")
    ok = ok and step("Mini Games (battle)", "Kart Battle")
    ok = ok and step("Kart Battle: settings", "Next")
    for label, anchor in (("Kart Battle: players", "Ready"), ("Kart Battle: settings again", "Rule: "),
                          ("Mini Games (after battle)", "Kart Battle"), ("Local Drive (after kart)", "Highway")):
        ok = ok and back_from(label, anchor)
    return ok


def racing_menus():
    """Main menu -> Local Drive -> Racing -> Stock Car -> its Settings page -> Players (no Class
    step: its class is fixed), and back; then the Time Trial switch -> Regular -> its Settings ->
    the class -> Players, and back, and Kart -> its Settings -> Players, and back; then Custom ->
    Save preset's page, its Settings -> the class, and back out (UI overhaul P4-P6,
    docs/UI_FLOW.md §5.3, §6.1)."""
    log("Racing")
    ok = step("Main menu (racing)", "Local Drive")
    ok = ok and step("Local Drive (racing)", "Racing")
    ok = ok and hidden("Racing", "Mini Games")
    ok = ok and step("Racing: Stock Car", "Stock Car")
    ok = ok and hidden("Stock Car: settings", "Custom")
    ok = ok and step("Stock Car: settings", "Next")
    ok = ok and back_from("Stock Car: players", "Ready")
    ok = ok and back_from("Stock Car: settings again", "Laps: ")
    ok = ok and step("Racing: to Time Trial", "Time Trial", role="toggle button")
    ok = ok and step("Racing: Regular time trial", "Regular")
    ok = ok and step("Regular time trial: settings", "Next")
    ok = ok and step("Regular time trial: class", "Track GT", prefix=True)
    # Time trials have a Players step (P6): splitscreen, each player with their own ghost.
    for label, anchor in (("Regular time trial: players", "Ready"), ("Regular time trial: class again", "Track GT"),
                          ("Regular time trial: settings again", "Next")):
        ok = ok and back_from(label, anchor)
    ok = ok and step("Racing: Kart time trial", "Kart")
    ok = ok and step("Kart time trial: settings", "Next")
    ok = ok and back_from("Kart time trial: players", "Ready")  # each card picks its class
    ok = ok and back_from("Kart time trial: settings again", "Next")
    ok = ok and step("Racing: back to Race", "Race", role="toggle button")
    # Custom (P5): its presets' name page, its Settings page, its class (any mode's).
    ok = ok and step("Racing: Custom", "Custom")
    ok = ok and step("Custom: settings", "Save preset")
    ok = ok and back_from("Custom: preset name", "Save")  # its Name field is a text field, not a button
    ok = ok and step("Custom: settings again", "Next")
    ok = ok and back_from("Custom: class", "Track GT")
    ok = ok and back_from("Custom: settings, back", "Preset: ")
    ok = ok and back_from("Racing (after Custom)", "Custom")
    ok = ok and back_from("Local Drive (after racing)", "Highway")
    if ok and find("Local Drive", "button", timeout=20.0) is None:
        problems.append("Out of Racing: no main menu")
        return False
    return ok


def endless_menus():
    """Main menu -> Local Drive -> Endless -> its Settings page -> the class -> Players, and back
    out (M9, UI overhaul P5)."""
    log("Endless pages")
    ok = step("Main menu (endless)", "Local Drive")
    ok = ok and step("Local Drive (endless)", "Endless")
    ok = ok and step("Endless: settings", "Next")
    ok = ok and step("Endless: class", "Endless Cruiser", prefix=True)
    for label, anchor in (("Endless: players", "Ready"), ("Endless: class again", "Endless Cruiser"),
                          ("Endless: settings again", "New road"), ("Local Drive (after endless)", "Endless")):
        ok = ok and back_from(label, anchor)
    return ok


def sumo_menus():
    """Main menu -> Local Drive -> Mini Games -> Sumo Wrestling -> its Settings page -> Players,
    and back out. No Class step: the mode has one class, and it makes its own arena (D162)."""
    log("Mini Games and Sumo Wrestling's pages")
    ok = step("Main menu (sumo)", "Local Drive")
    ok = ok and step("Local Drive (sumo)", "Mini Games")
    ok = ok and step("Mini Games", "Sumo Wrestling")
    ok = ok and step("Sumo: settings", "Next")
    for label, anchor in (("Sumo: players", "Ready"), ("Sumo: settings again", "Platforms: "),
                          ("Mini Games again", "Sumo Wrestling"), ("Local Drive (after sumo)", "Mini Games")):
        ok = ok and back_from(label, anchor)
    return ok


def drag_menus():
    """Main menu -> Local Drive -> Mini Games -> Drag Strip -> its Settings page -> the class
    (Street, Pro or Top Fuel) -> Players, and back out. The strip is made from the settings
    (D168)."""
    log("Mini Games and Drag Strip's pages")
    ok = step("Main menu (drag)", "Local Drive")
    ok = ok and step("Local Drive (drag)", "Mini Games")
    ok = ok and step("Mini Games (drag)", "Drag Strip")
    ok = ok and step("Drag: settings", "Next")
    ok = ok and step("Drag: class", "Drag Street", prefix=True)
    for label, anchor in (("Drag: players", "Ready"), ("Drag: class again", "Drag Street"),
                          ("Drag: settings again", "Boost: "), ("Mini Games again (drag)", "Drag Strip"),
                          ("Local Drive (after drag)", "Mini Games")):
        ok = ok and back_from(label, anchor)
    return ok


def free_menus():
    """Main menu -> Local Drive -> Free Drive -> its Settings page -> the class (every mode's) ->
    Players, and back out (UI overhaul P5)."""
    log("Free Drive's pages")
    ok = step("Main menu (free)", "Local Drive")
    ok = ok and step("Local Drive (free)", "Free Drive")
    ok = ok and step("Free Drive: settings", "Next")
    ok = ok and step("Free Drive: class", "Track GT", prefix=True)
    for label, anchor in (("Free Drive: players", "Ready"), ("Free Drive: class again", "Track GT"),
                          ("Free Drive: settings again", "Track: "), ("Local Drive (after free)", "Free Drive")):
        ok = ok and back_from(label, anchor)
    return ok


def settings_menus():
    """Main menu -> Settings -> every tab (Display's Reset to defaults and General's Clear downloads
    asking first: Keep) -> Players -> Profiles and back -> Driving Settings -> every tab (Comfort's
    Reset to defaults asking first), and back out (UI overhaul P3, P11; docs/UI_FLOW.md §9). The
    tabs are toggle buttons; each tab's screen is checked as the next one is pressed. The rows a
    long tab starts below the fold (Controls' Buttons and keys) are out of the screen-reader tree
    until focused (ARCHITECTURE §1): the tests open those pages."""
    log("Settings")
    ok = step("Main menu (settings)", "Settings")
    ok = ok and hidden("Settings", "Local Drive")
    ok = ok and asks("Settings: Display", "Reset to defaults", "Graphics: ")  # Display is open first
    for tab in ("Sound", "Splitscreen", "General"):
        ok = ok and step(f"Settings: to {tab}", tab, role="toggle button")
    ok = ok and asks("Settings: General", "Clear downloads", "Units: ", prefix=True)
    ok = ok and step("Settings: to Players", "Players", role="toggle button")
    ok = ok and step("Settings: Players", "Profiles")
    ok = ok and back_from("Profiles", "New profile")
    if ok and find("Profiles", "button", timeout=20.0) is None:  # Profiles has its own Driving Settings
        problems.append("Out of Profiles: no Players tab")
        ok = False
    ok = ok and step("Settings: Players again", "Driving Settings")
    ok = ok and hidden("Driving Settings", "Profiles")
    ok = ok and step("Driving Settings: to Comfort", "Comfort", role="toggle button")
    ok = ok and asks("Driving Settings: Comfort", "Reset to defaults", "Reset to defaults")
    for tab in ("Vision & Hearing", "HUD & Display", "Controls", "Assists"):
        ok = ok and step(f"Driving Settings: to {tab}", tab, role="toggle button")
    ok = ok and back_from("Driving Settings: Assists", "Auto gearbox")
    ok = ok and back_from("Settings: Players again", "Profiles")
    if ok and find("Local Drive", "button", timeout=20.0) is None:
        problems.append("Out of Settings: no main menu")
        return False
    return ok


def garage_menus():
    """Main menu -> Garage -> its tabs (Built-in) -> nOSS Box's page (the grid hidden under it) ->
    Drive -> the class page and back -> Back -> My cars -> Fitting Bay -> the Import step's "From
    online games" list -> Exit -> the Garage again -> Back (UI overhaul P7, P7b, P11;
    docs/UI_FLOW.md §5.6, §8)."""
    log("Garage")
    ok = step("Main menu (garage)", "Garage")
    ok = ok and step("Garage: to Built-in", "Built-in", role="toggle button")
    if ok and find("nOSS Box", "button", timeout=20.0) is None:  # the tab has switched
        problems.append("Garage: Built-in shows no 'nOSS Box'")
        ok = False
    ok = ok and step("Garage: Built-in", "nOSS Box")
    if ok and find("Drive", "button", timeout=20.0) is None:
        problems.append("nOSS Box's page: no 'Drive'")
        ok = False
    ok = ok and hidden("nOSS Box's page", "New car")
    ok = ok and step("nOSS Box's page", "Drive")
    ok = ok and hidden("nOSS Box: class", "Duplicate")
    ok = ok and back_from("nOSS Box: class", "Track GT")  # every class that takes the car, any mode's
    ok = ok and back_from("nOSS Box's page again", "Duplicate")
    ok = ok and step("Garage: to My cars", "My cars", role="toggle button")
    end = time.time() + 20.0
    while ok and find("nOSS Box", "button", timeout=0.5) is not None:  # until the tab has switched
        if time.time() > end:
            problems.append("Garage: My cars still shows 'nOSS Box'")
            ok = False
    ok = ok and step("Garage", "Fitting Bay")
    if ok and find("From online games", timeout=20.0) is None:
        problems.append("Fitting Bay: no 'From online games' list")
        ok = False
    ok = ok and step("Fitting Bay: Import", "Exit")
    if ok and find("New car", "button", timeout=20.0) is None:  # Exit goes back to the Garage
        problems.append("Out of the Fitting Bay: no Garage")
        ok = False
    ok = ok and step("Garage again", "Back")
    if ok and find("Local Drive", "button", timeout=20.0) is None:
        problems.append("Out of the Garage: no main menu")
        return False
    return ok


def online_menus():
    """Main menu -> Drive Online -> Host -> Next -> the Event page -> Racing -> the Time Trial switch
    -> Regular -> its Settings page (a timed session: Minutes) and back -> Race -> Regular -> its
    Settings page -> the class, which hosts -> the lobby: Ready (not pressed: the countdown would
    start), Change event (the lobby hidden under it) and back, Playlist and back, P1's row to This
    PC's rows, Driving Settings and back -> Leave; then Join -> Direct -> On your network (Official
    is off) -> Back -> Back (M5, UI overhaul P8-P10; docs/UI_FLOW.md §7)."""
    log("Drive Online")
    ok = step("Main menu (online)", "Drive Online")
    ok = ok and hidden("Drive Online", "Local Drive")
    ok = ok and step("Drive Online", "Host")
    ok = ok and hidden("Host", "Join")
    ok = ok and step("Host", "Next")
    ok = ok and step("Host: event", "Racing")
    # Time trials host too (P10): the switch, and a timed session's Minutes.
    ok = ok and step("Host: racing, to Time Trial", "Time Trial", role="toggle button")
    time.sleep(1.5)  # the switch makes the types again: not the Regular being freed
    ok = ok and step("Host: Regular time trial", "Regular")
    if ok and find("Minutes: ", "button", timeout=20.0, prefix=True) is None:
        problems.append("Host: a time trial's settings have no 'Minutes' row")
        names = sorted({f"{n.get_role_name()} '{n.get_name()}'" for n in walk(app()) if showing(n) and (n.get_name() or "")})
        log(f"  showing: {', '.join(names[:40])}")
        ok = False
    ok = ok and back_from("Host: time trial settings", "Minutes: ")
    ok = ok and step("Host: racing, back to Race", "Race", role="toggle button")
    ok = ok and step("Host: racing", "Regular")
    ok = ok and hidden("Host: settings", "Stock Car")
    ok = ok and step("Host: settings", "Next")
    ok = ok and step("Host: class", "Track GT", prefix=True)
    if ok and find("Leave", "button", timeout=20.0) is None:
        problems.append("Lobby: no Leave button")
        ok = False
    if ok:
        find(", host", "button", timeout=10.0, contains=True)  # the list (P1's row) arrives a tick later
        for name in ("Ready", "Change event", "Playlist", "Force start"):
            if find(name, "button", timeout=5.0) is None:
                problems.append(f"Lobby: no '{name}' button")
                ok = False
        ok = ok and step("Lobby", "Change event")
        ok = ok and hidden("Lobby: Change event", "Playlist")
        ok = ok and back_from("Lobby: Change event", "Racing")
        ok = ok and step("Lobby again", "Playlist")
        if ok and find("1. ", "toggle button", timeout=10.0, prefix=True) is None:
            problems.append("Playlist: no events listed")
            ok = False
        ok = ok and back_from("Lobby: Playlist", "Add event")
        # P1's own row brings This PC into view (rows that start below the fold aren't in the tree).
        ok = ok and step("Lobby again", ", host", contains=True)
        for name in ("Profile: ", "Car: ", "Controls: ", "Driving Settings"):
            if ok and find(name, "button", timeout=5.0, prefix=name.endswith(": ")) is None:
                problems.append(f"Lobby: no '{name.rstrip(': ')}' button under This PC")
                ok = False
        ok = ok and step("Lobby: This PC", "Driving Settings")
        ok = ok and hidden("Lobby: Driving Settings", "Ready")
        ok = ok and back_from("Lobby: Driving Settings", "Auto gearbox")
        ok = ok and step("Lobby", "Leave")
    ok = ok and step("Drive Online again", "Join")
    ok = ok and step("Join: On your network", "Direct", role="toggle button")
    # Godot 4.7.2 doesn't tell AT-SPI a button is disabled: the Official tab is off if it can't
    # take the focus, and its description says why.
    official = find("Official", "toggle button", timeout=5.0) if ok else None
    if ok and official is None:
        problems.append("Join: no 'Official' tab")
    elif official is not None and (states(official) is None or states(official).contains(Atspi.StateType.FOCUSABLE)
                                   or official.get_description() != "Coming soon"):
        problems.append("Join: the Official tab is on, or doesn't say 'Coming soon'")
    ok = ok and step("Join: Direct", "On your network", role="toggle button")
    ok = ok and step("Join: On your network again", "Back")
    ok = ok and back_from("Drive Online (after join)", "Host")
    if ok and find("Local Drive", "button", timeout=20.0) is None:
        problems.append("Out of Drive Online: no main menu")
        return False
    return ok


def asks(label, name, anchor, prefix=False):
    """Presses `name`, which asks first (a ConfirmPage: docs/UI_FLOW.md §4), checks the question
    and answers "Keep"; the screen with `anchor` (a name prefix) comes back."""
    ok = step(label, name, prefix=prefix)
    ok = ok and hidden(f"{label}: the question", anchor, prefix=True)
    ok = ok and step(f"{label}: the question", "Keep")
    if ok and find(anchor, "button", timeout=20.0, prefix=True) is None:
        problems.append(f"{label}: no '{anchor}' after Keep")
        return False
    return ok


def hidden(label, name, prefix=False):
    """Only the top page shows (docs/UI_FLOW.md §4): `name`, a button of the screen under it,
    isn't showing, so a screen reader can't reach it."""
    time.sleep(1.0)  # the new page is up a frame after the press
    if find(name, "button", timeout=2.0, prefix=prefix) is not None:
        problems.append(f"{label}: '{name}' from the screen under it is still showing")
        return False
    log(f"  '{name}' is hidden under it")
    return True


def back_from(label, anchor):
    """Waits for the screen with `anchor` (a name prefix), checks it, and presses its Back."""
    if find(anchor, "button", timeout=30.0, prefix=True) is None:
        problems.append(f"{label}: no '{anchor}' button")
        return False
    time.sleep(1.5)  # the screen before is freed meanwhile
    return step(label, "Back", last=True)


def highway_pause_walk():
    """A highway session with two players (one autodriven), the last one's pause menu open in their
    view: its controls, its Driving Settings and back (P11), then joining the other player from it
    (M7)."""
    log("Highway session: pause")
    game, _ = start_game(["--highway", "--players=2", "--pause-at=12"], "noss_a11y_highway.log")
    try:
        if find("Change direction", "button", timeout=120.0) is None:
            problems.append("Highway pause: no 'Change direction' button")
            return
        if step("Highway pause", "Driving Settings"):
            hidden("Pause: Driving Settings", "Change direction")
            back_from("Pause: Driving Settings", "Auto gearbox")
            if find("Change direction", "button", timeout=20.0) is None:
                problems.append("Out of the pause's Driving Settings: no pause menu")
                return
        step("Highway pause", "Join ", prefix=True)
        time.sleep(2.0)
        if find("Change direction", "button", timeout=2.0) is not None:
            problems.append("Highway pause: still open after joining a friend")
    finally:
        stop_game(game)


def first_boot_walk():
    """The first-boot Accessibility screen (ACC-09, docs/ACCESSIBILITY.md §7; --menu=access opens it
    though this run skips first boot): its Driving Settings and back, then Done to the main menu."""
    log("First boot")
    game, _ = start_game(["--menu=access"], "noss_a11y_first_boot.log")
    try:
        if find("Done", "button", timeout=60.0) is None:
            problems.append("First boot: no 'Done' button")
            return
        ok = step("First boot", "Driving Settings")
        ok = ok and hidden("First boot: Driving Settings", "Done")
        ok = ok and back_from("First boot: Driving Settings", "Auto gearbox")
        ok = ok and step("First boot again", "Done")
        if ok and find("Local Drive", "button", timeout=20.0) is None:
            problems.append("After first boot: no main menu")
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
    if not step("Main menu (editor)", "Track Editor"):
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
        problems.append("Out of the editor: no main menu")


def race_walk():
    """Main menu -> Local Drive -> Racing -> Regular -> its Settings page -> the class -> Players ->
    a 1-lap race (autodriven) -> the results, which have "Main menu"; their "Event menu" -> that
    event's Settings page and back out to Local Drive -> Drive again -> Players, and back out a page
    at a time to the main menu (M4 acceptance; UI overhaul P4, P11; docs/UI_FLOW.md §5.2, §5.9).
    Each page on the way in hides the one under it (P2)."""
    log("Race")
    ok = step("Main menu", "Local Drive")
    ok = ok and hidden("Local Drive", "Drive Online")
    ok = ok and step("Local Drive", "Racing")
    ok = ok and hidden("Racing", "Mini Games")
    ok = ok and step("Racing", "Regular")
    ok = ok and hidden("Settings", "Stock Car")
    ok = ok and step("Settings", "Next")
    ok = ok and step("Class", "Track GT", prefix=True)
    ok = ok and step("Players", "Ready", timeout=30.0)
    if not ok:
        return False
    log("Race (1 lap, autodrive)")
    row = find("P1, ", "button", timeout=240.0, prefix=True)
    if row is None:
        problems.append("Results: no result rows (the race didn't finish?)")
        return False
    rows = [n for n in walk(app()) if (n.get_name() or "").startswith("P") and ", " in (n.get_name() or "") and showing(n)]
    log(f"  {len(rows)} result rows, e.g. '{row.get_name()}'")
    if find("Main menu", "button", timeout=5.0) is None:
        problems.append("Results: no 'Main menu' button")
    ok = step("Results", "Event menu")
    ok = ok and back_from("Settings (Event menu)", "Laps: ")
    ok = ok and back_from("Racing (Event menu)", "Custom")
    ok = ok and step("Local Drive (Drive again)", "Drive again")
    for label, anchor in (("Drive again: players", "Ready"), ("Drive again: settings", "Laps: "),
                          ("Drive again: racing", "Custom"), ("Local Drive (after Drive again)", "Highway")):
        ok = ok and back_from(label, anchor)
    if ok and find("Local Drive", "button", timeout=20.0) is None:
        problems.append("Out of Drive again: no main menu")
        return False
    return ok


# The routes from the main menu, in the full walk's order after the race: each starts and ends
# there. --<name>-only runs just those named.
ROUTES = [
    ("racing", racing_menus),
    ("online", online_menus),
    ("highway", highway_menus),
    ("kart", kart_menus),
    ("endless", endless_menus),
    ("sumo", sumo_menus),
    ("drag", drag_menus),
    ("free", free_menus),
    ("settings", settings_menus),
    ("garage", garage_menus),
    ("editor", editor_walk),
]
# Walks in a game of their own, after the main one; --highway-only runs the pause one too.
OWN_GAME = [
    ("highway", highway_pause_walk),
    ("first-boot", first_boot_walk),
]


def main():
    subprocess.run(["busctl", "--user", "set-property", "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status", "IsEnabled", "b", "true"],
                   check=False, capture_output=True)
    names = {name for name, _ in ROUTES + OWN_GAME}
    only = {a[2:-5] for a in sys.argv[1:] if a.startswith("--") and a.endswith("-only") and a[2:-5] in names}
    unknown = [a for a in sys.argv[1:] if a.startswith("--") and a[2:-5] not in names]
    if unknown:
        log(f"Unknown: {' '.join(unknown)} (routes: {', '.join(sorted(names))})")
        return 2
    routes = [w for name, w in ROUTES if not only or name in only]
    if routes:
        game, _ = start_game([], "noss_a11y_check.log")
        try:
            if find("Local Drive", "button", timeout=60.0) is None:
                problems.append("No main menu")
            elif only or race_walk():
                for w in routes:
                    if find("Local Drive", "button", timeout=20.0) is None:
                        problems.append(f"Before the {w.__name__} route: no main menu")
                        break
                    w()
        finally:
            stop_game(game)
    for name, w in OWN_GAME:
        if not only or name in only:
            w()
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
