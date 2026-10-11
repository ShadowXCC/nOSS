class_name NetChat
extends RefCounted
## Online chat (MP-07, docs/NETWORKING.md §4): text only, short, rate limited by the server, and
## muted per player by each client. Lines starting with "/" are commands for admins.

const MAX_CHARS := 200
## Each connection may send this many lines per WINDOW_S.
const BURST := 5
const WINDOW_S := 5.0
## Quick lines for controller players (no typing).
const QUICK := ["GG", "Sorry", "Thanks", "Nice race", "Wait", "Ready"]
const COMMANDS := {
	"help": "Commands: /kick <name>, /ban <name>, /start, /next, /restart",
	"kick": "", "ban": "", "start": "", "next": "", "restart": "",
}


## One line: printable, single-line and trimmed, at most MAX_CHARS.
static func clean(text: String) -> String:
	var out := ""
	for c in text:
		var u := c.unicode_at(0)
		if u == 9 or u == 10 or u == 13:
			out += " "
		elif u >= 32 and u != 127 and not (u >= 0x200B and u <= 0x200F) and not (u >= 0x202A and u <= 0x202E):
			out += c
	return out.strip_edges().left(MAX_CHARS)


## For text shown through BBCode (chat lines themselves are added as plain text).
static func escape_bbcode(text: String) -> String:
	return text.replace("[", "[lb]")


## {cmd, arg} for "/kick Ann", or {} for normal text.
static func command(text: String) -> Dictionary:
	if not text.begins_with("/"):
		return {}
	var parts := text.substr(1).split(" ", false, 1)
	if parts.is_empty():
		return {}
	return { "cmd": parts[0].to_lower(), "arg": parts[1].strip_edges() if parts.size() > 1 else "" }


## Keeps the times of each sender's recent lines; allow() says whether one more may go now.
class Limiter:
	var _times := {} # key -> Array of times (s)

	func allow(key: Variant, now: float) -> bool:
		var list: Array = _times.get(key, [])
		while not list.is_empty() and now - float(list[0]) > WINDOW_S:
			list.pop_front()
		if list.size() >= BURST:
			_times[key] = list
			return false
		list.append(now)
		_times[key] = list
		return true

	func forget(key: Variant) -> void:
		_times.erase(key)
