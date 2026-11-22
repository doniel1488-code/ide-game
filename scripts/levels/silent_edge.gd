extends RefCounted

const RELAYS: Array[Vector3] = [Vector3(-8, 0, -10), Vector3(0, 0, -18), Vector3(11, 0, -12)]
const MEMORIES: Array[Vector3] = [
	Vector3(-9, 0.5, -11), Vector3(-4, 0.5, -17), Vector3(2, 0.5, -13),
	Vector3(8, 0.5, -15), Vector3(11, 0.5, -8), Vector3(8, 0.5, -2),
]
const ROCKS: Array[Vector3] = [
	Vector3(-11, 0, -5), Vector3(-17, 0, -10), Vector3(18, 0, -17),
	Vector3(15, 0, 8), Vector3(-16, 0, 5), Vector3(2, 0, 13),
	Vector3(-3, 0, -12), Vector3(7, 0, 11),
]
const DRONES: Array[Vector3] = [Vector3(-15, 0.5, -15), Vector3(15, 0.5, -6)]
const OUTER_RELAY := Vector3(-17, 1, -21)
const WRECK := Vector3(14, -2, -23)

const NAVIGATION_RADIUS := 37.0
