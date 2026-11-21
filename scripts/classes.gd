class_name Classes
extends RefCounted
## Who you are on the Isle: four classes, one attack, one alternate, one
## ability and one passive each. Low complexity, high skill.
##
## The choice is kept in the profile and used in every mode.

const ORDER := ["knight", "hunter", "pyro", "gunslinger"]

const DEFS := {
	"knight": {
		"name": "THE KNIGHT",
		"tag": "SWORD AND SHIELD",
		"color": Color(0.95, 0.62, 0.3),
		"difficulty": 1,
		"weapon": "ASHEN GREATSWORD",
		"attack": "Three-swing combo. Keep clicking: the third is a heavy overhead.",
		"alt": "GUARD (hold): blocks 80% from the front. Raise it just as a blow lands to PARRY: no damage, the attacker reels.",
		"ability": "SHIELD CHARGE: dash forward, bash and stagger everything in your way.",
		"passive": "+25 health. Takes 10% less from the front.",
		"style": "Close in, read the swing, parry, punish.",
		"cd": 7.0,
	},
	"hunter": {
		"name": "THE HUNTER",
		"tag": "LONGBOW",
		"color": Color(0.55, 0.9, 0.45),
		"difficulty": 2,
		"weapon": "YEW LONGBOW",
		"attack": "Hold to draw, release to loose. A full draw flies flat and hits hard; arrows drop with distance.",
		"alt": "FOCUS (hold): zoom in and steady the draw.",
		"ability": "VOLLEY: three full-power arrows at once, in a tight fan.",
		"passive": "Faster sprint, quieter steps. Headshots deal double.",
		"style": "Keep your distance, lead your shots, never stand still.",
		"cd": 8.0,
	},
	"pyro": {
		"name": "THE PYROMANCER",
		"tag": "EMBER STAFF",
		"color": Color(1.0, 0.45, 0.2),
		"difficulty": 2,
		"weapon": "EMBER STAFF",
		"attack": "Fireballs that burst and leave the ground burning. Each costs Ember.",
		"alt": "FLAME WALL (hold): a cone of fire up close. Burns Ember fast.",
		"ability": "BLINK: step through space, a few metres ahead.",
		"passive": "Ember refills on its own, and a kill refills a lot of it.",
		"style": "Control space, burn corners, blink out of trouble.",
		"cd": 5.0,
	},
	"gunslinger": {
		"name": "THE GUNSLINGER",
		"tag": "RIFLE AND REVOLVER",
		"color": Color(0.5, 0.75, 1.0),
		"difficulty": 1,
		"weapon": "ANY GUN",
		"attack": "The guns you know: rifles, shotguns, snipers, pistols.",
		"alt": "AIM down the sights.",
		"ability": "QUICKDRAW: instant reload, and your next shots fire faster.",
		"passive": "Reloads 20% faster. Ammo boxes give more.",
		"style": "The steady all-rounder. Good at every range.",
		"cd": 10.0,
	},
}

## What each class looks like to everyone else (and on the menu).
const SKINS := {
	"knight": "res://assets/characters/gobkit/medieval/KnightCaptain.glb",
	"hunter": "res://assets/characters/gobkit/medieval/Archer.glb",
	"pyro": "res://assets/characters/gobkit/medieval/Priestess.glb",
	"gunslinger": "res://assets/characters/gobkit/soldiers/FrontlineRifleman.glb",
}

static var chosen := "knight"
static var _loaded := false
## Tests leave the player's profile alone.
static var no_save := false


static func def(c: String) -> Dictionary:
	return DEFS.get(c, DEFS["gunslinger"])


static func has_kit(c: String) -> bool:
	return c in ["knight", "hunter", "pyro"]


static func load_choice() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load("user://profile.cfg") == OK:
		var c := str(cf.get_value("class", "chosen", "knight"))
		if DEFS.has(c):
			chosen = c


static func choose(c: String) -> void:
	if not DEFS.has(c):
		return
	chosen = c
	_loaded = true
	if no_save:
		return
	var cf := ConfigFile.new()
	cf.load("user://profile.cfg")
	cf.set_value("class", "chosen", c)
	cf.save("user://profile.cfg")
