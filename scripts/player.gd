class_name Player
extends CharacterBody3D
## Joueur. Simulé uniquement par le serveur ; les clients interpolent les snapshots reçus.

const SPEED := 7.0
const JUMP_VELOCITY := 7.0
const GRAVITY := 20.0
const MAX_SNAPSHOTS := 30

var peer_id := 0
var is_local := false

# Serveur : dernier input reçu du client.
var input_move := Vector2.ZERO
var input_yaw := 0.0
var input_jump := false

# Client : snapshots reçus, [tick, position, yaw], triés par tick.
var _snapshots: Array = []


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(fmod(peer_id * 0.618034, 1.0), 0.7, 0.9)
	$Body.material_override = mat


## Serveur : avance la simulation d'un tick à partir du dernier input.
func simulate(delta: float) -> void:
	rotation.y = input_yaw
	var dir := (transform.basis * Vector3(input_move.x, 0.0, input_move.y)).normalized()
	velocity.x = dir.x * SPEED
	velocity.z = dir.z * SPEED

	if is_on_floor():
		if input_jump:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= GRAVITY * delta

	move_and_slide()


## Client : enregistre un état reçu du serveur.
func push_snapshot(tick: int, pos: Vector3, yaw: float) -> void:
	if not _snapshots.is_empty() and tick <= _snapshots[-1][0]:
		return
	_snapshots.append([tick, pos, yaw])
	if _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


## Client : place le joueur entre les deux snapshots qui encadrent render_tick.
func interpolate(render_tick: float) -> void:
	if _snapshots.is_empty():
		return
	while _snapshots.size() >= 2 and _snapshots[1][0] <= render_tick:
		_snapshots.pop_front()

	var a: Array = _snapshots[0]
	if _snapshots.size() == 1 or render_tick <= a[0]:
		global_position = a[1]
		rotation.y = a[2]
		return

	var b: Array = _snapshots[1]
	var t := (render_tick - a[0]) / float(b[0] - a[0])
	global_position = a[1].lerp(b[1], t)
	rotation.y = lerp_angle(a[2], b[2], t)
