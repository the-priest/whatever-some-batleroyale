extends RefCounted
class_name Prof

## Tiny frame profiler for the --perf test: per-system microseconds.
static var on := false
static var acc: Dictionary = {}
static var peak: Dictionary = {}


static func add(key: String, usec: int) -> void:
	if not on:
		return
	acc[key] = int(acc.get(key, 0)) + usec


static func reset() -> void:
	acc.clear()
	peak.clear()
