class_name Hurtbox
extends StaticBody3D
## The part of a body that is shot, not the part that walks: the boxes fitted
## to a character's real shape sit on this (layer 4, colliding with nothing),
## so they can be as wide as the character's arms and weapon without snagging
## on doorways or shoving the next boss. Everything asked of it is answered
## by the body it belongs to.

var owner_bot: Node = null


func _init() -> void:
	collision_layer = 4
	collision_mask = 0


func take_damage(amount: float, pos: Vector3 = Vector3.ZERO, headshot: bool = false, source: Node = null) -> bool:
	if owner_bot == null or not is_instance_valid(owner_bot):
		return false
	return owner_bot.take_damage(amount, pos, headshot, source)


func head_y() -> float:
	if owner_bot != null and is_instance_valid(owner_bot) and owner_bot.has_method("head_y"):
		return owner_bot.head_y()
	return global_position.y + 99.0


func _get(property: StringName) -> Variant:
	if owner_bot != null and is_instance_valid(owner_bot) and property in ["alive", "friendly", "helmet_level", "vest_level", "armor", "is_human", "puppet"]:
		return owner_bot.get(property)
	return null


## The body a hit on this collider is really on.
static func resolve(col: Object) -> Object:
	if col is Hurtbox:
		return (col as Hurtbox).owner_bot
	return col
