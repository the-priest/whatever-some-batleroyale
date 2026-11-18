class_name Renown
extends RefCounted
## Renown: what you are known for across every match you play, kept in the
## player's profile. Each match pays Renown for how long you lasted, the
## kills, the writs, the Revenants, the vaults; Oaths sworn before a solo
## match make it harder and pay more.

const PATH := "user://profile.cfg"
const RANKS := [
	[0, "ASHEN"], [600, "WANDERER"], [1600, "SELLSWORD"], [3200, "HUNTER"], [5500, "WARDEN"],
	[8500, "CHAMPION"], [12500, "REVENANT-SLAYER"], [18000, "LEGEND OF THE ISLE"],
]
## [id, name, what it does]. Each sworn Oath adds a quarter to the Renown a
## solo match pays.
const OATHS := [
	["iron", "OATH OF IRON", "Soldiers take a third less damage"],
	["embers", "OATH OF EMBERS", "Wayshrines charge double"],
	["hunted", "OATH OF THE HUNTED", "You land Branded"],
	["silence", "OATH OF SILENCE", "No minimap"],
	["ash", "OATH OF ASH", "No Kindling"],
	["glass", "OATH OF GLASS", "You have 75 health"],
]
const OATH_BONUS := 0.25

static var total := 0
static var matches := 0
static var best := 0
static var sworn: Dictionary = {}
static var _loaded := false


static func load_profile() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	total = int(cfg.get_value("renown", "total", 0))
	matches = int(cfg.get_value("renown", "matches", 0))
	best = int(cfg.get_value("renown", "best", 0))
	for o in OATHS:
		if bool(cfg.get_value("oaths", o[0], false)):
			sworn[o[0]] = true


static func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	cfg.set_value("renown", "total", total)
	cfg.set_value("renown", "matches", matches)
	cfg.set_value("renown", "best", best)
	for o in OATHS:
		cfg.set_value("oaths", o[0], sworn.has(o[0]))
	cfg.save(PATH)


static func rank_of(r: int) -> int:
	var i := 0
	for k in RANKS.size():
		if r >= int(RANKS[k][0]):
			i = k
	return i


static func rank_name(r: int = -1) -> String:
	return str(RANKS[rank_of(total if r < 0 else r)][1])


## Progress through the current rank: [into it, its size] (size 0 at the top).
static func progress(r: int = -1) -> Array:
	var v := total if r < 0 else r
	var i := rank_of(v)
	if i >= RANKS.size() - 1:
		return [v - int(RANKS[i][0]), 0]
	return [v - int(RANKS[i][0]), int(RANKS[i + 1][0]) - int(RANKS[i][0])]


static func oath_mult() -> float:
	return 1.0 + OATH_BONUS * float(sworn.size())


## What a match paid, item by item: [[label, amount], ...] and the total.
static func tally(t: Dictionary, solo: bool) -> Array:
	var lines: Array = []
	var placement := int(t.get("placement", 1))
	var field := maxi(2, int(t.get("field", 2)))
	lines.append(["SURVIVAL", int(round(450.0 * float(field - placement) / float(field - 1)))])
	if bool(t.get("won", false)):
		lines.append(["VICTORY", 600])
	for k in [["kills", "KILLS", 25], ["writs", "WRITS FULFILLED", 120], ["revenants", "REVENANTS FELLED", 300],
			["vaults", "VAULTS OPENED", 150], ["blessings", "BLESSINGS", 40]]:
		var n := int(t.get(k[0], 0))
		if n > 0:
			lines.append(["%s  ×%d" % [k[1], n], n * int(k[2])])
	var sum := 0
	for l in lines:
		sum += int(l[1])
	if solo and not sworn.is_empty():
		var extra := int(round(float(sum) * (oath_mult() - 1.0)))
		lines.append(["OATHS SWORN  ×%d" % sworn.size(), extra])
		sum += extra
	return [lines, sum]


static func add(amount: int) -> void:
	total += amount
	matches += 1
	best = maxi(best, amount)
	save_profile()
