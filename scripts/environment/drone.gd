extends Node3D

const HUNTER := preload("res://assets/models/hunter.glb")
const WISP := preload("res://assets/models/wisp.glb")

var wisp := false

func _ready() -> void:
	var model: Node3D = (WISP if wisp else HUNTER).instantiate()
	add_child(model)
