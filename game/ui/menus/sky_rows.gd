class_name SkyRows
extends RefCounted
## The sky rows every event menu has (ENV-03, D153): the time of day, how fast it runs, and the
## weather. "Track's" keeps the track's own (its fixed sun, its weather).

const TIMES := [["track", "Track's"], ["dawn", "Dawn"], ["morning", "Morning"], ["noon", "Noon"], ["afternoon", "Afternoon"],
	["dusk", "Dusk"], ["night", "Night"]]
const RATES := [[0, "Still"], [1, "Real time"], [10, "10x"], [30, "30x"], [60, "60x"], [120, "120x"]]
const WEATHERS := [["track", "Track's"], ["clear", "Clear"], ["cloudy", "Cloudy"], ["rain", "Rain"], ["storm", "Storm"],
	["fog", "Fog"], ["snow", "Snow"], ["changing", "Changing"]]


## Spinners for `event`'s time, time rate and weather.
static func rows(event: RaceEvent) -> Array[Control]:
	var out: Array[Control] = []
	out.append(UiKit.spinner("Time", TIMES, event.time if event.time in RaceEvent.CHOICES.time else "track",
		func(v: String) -> void: event.time = v, "Time of day. Track's: the track's own light"))
	out.append(UiKit.spinner("Time runs", RATES, event.time_rate if event.time_rate in RaceEvent.TIME_RATES else 0,
		func(v: int) -> void: event.time_rate = v, "How fast the day goes by"))
	out.append(UiKit.spinner("Weather", WEATHERS, event.weather if event.weather in RaceEvent.CHOICES.weather else "track",
		func(v: String) -> void: event.weather = v, "Changing: it clears, clouds over, rains and fogs in turn"))
	return out
