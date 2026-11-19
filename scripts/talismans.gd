class_name Talismans
extends RefCounted
## Talismans: one from every kind of boss, yours for good once you have slain
## one with your own hand. Wear them from the main menu, as many as your five
## notches hold; each changes how you fight, in every match and in the Ordeal.

## [id, name, the boss it comes from, notches, what it does]
const LIST := [
	["iron", "TALISMAN OF IRON", "revenant", 2, "Bullets and blows hurt you a tenth less"],
	["ash", "ASHEN STEP", "warden", 2, "Your roll is ready again much sooner"],
	["giant", "GIANT'S HEART", "colossus", 3, "+30 maximum health"],
	["bell", "QUIET BELL", "bell", 2, "Your roll keeps you untouchable for longer"],
	["scale", "WYRM SCALE", "wyrm", 2, "One more swallow in the Ember Flask"],
	["feather", "CARRION FEATHER", "carrion", 1, "You jump higher"],
	["lantern", "WITCH'S LANTERN", "witch", 1, "You drink from the flask twice as fast"],
	["crown", "UNKINDLED CROWN", "unkindled", 3, "Your bullets hit a tenth harder"],
]
const NOTCHES := 5
const PATH := "user://profile.cfg"

static var worn: Dictionary = {}
static var _loaded := false
## Headless checks: wear what they like without touching the profile.
static var no_save := false


static func load_worn() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for t in LIST:
		if bool(cfg.get_value("talismans", t[0], false)):
			worn[t[0]] = true


static func save_worn() -> void:
	if no_save:
		return
	var cfg := ConfigFile.new()
	cfg.load(PATH)
	for t in LIST:
		cfg.set_value("talismans", t[0], worn.has(t[0]))
	cfg.save(PATH)


static func info(id: String) -> Array:
	for t in LIST:
		if t[0] == id:
			return t
	return []


## Yours: its boss has fallen to your hand.
static func owned(id: String) -> bool:
	var t := info(id)
	if t.is_empty():
		return false
	Ordeal.load_record()
	return Ordeal.slain.has(str(t[2]))


static func used() -> int:
	var n := 0
	for t in LIST:
		if worn.has(t[0]) and owned(t[0]):
			n += int(t[3])
	return n


## Worn now (and yours).
static func wears(id: String) -> bool:
	return worn.has(id) and owned(id)


## Put it on or take it off. False if it cannot go on (not yours, no room).
static func toggle(id: String) -> bool:
	load_worn()
	if worn.has(id):
		worn.erase(id)
		save_worn()
		return true
	var t := info(id)
	if t.is_empty() or not owned(id) or used() + int(t[3]) > NOTCHES:
		return false
	worn[id] = true
	save_worn()
	return true
