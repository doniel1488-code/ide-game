extends Camera3D

const OFFSET := Vector3(0, 14, 21)
var aim := Vector3.ZERO

func reset_to(target: Vector3) -> void:
	position = target + OFFSET
	aim = target + Vector3(0, 0, -2)
	look_at(aim)

func follow(target: Vector3, velocity: Vector3, delta: float) -> void:
	var weight := 1.0 - exp(-5.0 * delta)
	var ahead := (velocity * 0.18).limit_length(3.0)
	position = position.lerp(target + OFFSET + ahead * 0.5, weight)
	aim = aim.lerp(target + Vector3(0, 0, -2) + ahead, weight)
	look_at(aim)
