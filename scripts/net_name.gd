extends Node

## Stand-in damage source for hits whose shooter is not known locally.
var shown_name := "SOMEONE"


func display_name() -> String:
	return shown_name
