class_name ChestBody
extends StaticBody3D
## The solid part of a chest. When it is an awake Mimic, bullets and blasts
## hurt it (they find take_damage here); the host settles the hit.

var chests: Node = null
var index := -1
## Bullets only count a hit on something "alive".
var alive: bool:
	get:
		return chests != null and chests.state[index] == "awake"


func take_damage(amount: float, _pos: Vector3 = Vector3.ZERO, _headshot: bool = false, source: Node = null) -> bool:
	if chests == null:
		return false
	if chests.game.net_is_client():
		chests.game.net.send_chest(index, "hit", amount)
		return false
	chests.hit_on(index, amount, source)
	return chests.state[index] == "dead"
