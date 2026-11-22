extends Node
## Point d'entrée commun au client et au serveur dédié.
## Les RPC passent toutes par ce nœud (/root/Main), identique des deux côtés.

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const SNAPSHOT_INTERVAL := 2 # ticks entre deux snapshots : 60 Hz / 2 = 30 Hz
const INTERP_DELAY_TICKS := 6.0 # les autres joueurs sont affichés ~100 ms dans le passé
const MOUSE_SENSITIVITY := 0.003
const KILL_HEIGHT := -20.0

@onready var players_root: Node3D = $Players
@onready var spawn_points: Node3D = $Arena/SpawnPoints

var players := {} # peer_id -> Player

# Serveur
var _running := false
var _tick := 0
var _next_spawn := 0

# Client
var _connected := false
var _server_tick := 0.0 # estimation du tick serveur courant
var _has_snapshot := false
var _yaw := 0.0
var _pitch := -0.3
var _camera_rig: Node3D
var _menu: Control
var _status: Label
var _join_button: Button


func _ready() -> void:
	if Net.is_server:
		_start_server()
	else:
		_setup_input_map()
		_build_camera()
		_build_menu()
		Net.connected.connect(_on_connected)
		Net.connection_failed.connect(_on_connection_failed)
		Net.disconnected.connect(_on_disconnected)


func _physics_process(delta: float) -> void:
	if Net.is_server:
		_server_tick_step(delta)
	elif _connected:
		_send_input()


func _process(delta: float) -> void:
	if Net.is_server:
		return

	if _has_snapshot:
		_server_tick += delta * Net.TICK_RATE
		var render_tick := _server_tick - INTERP_DELAY_TICKS
		for p: Player in players.values():
			p.interpolate(render_tick)

	var me: Player = players.get(multiplayer.get_unique_id())
	if me:
		var target := me.global_position + Vector3(0.0, 1.5, 0.0)
		_camera_rig.global_position = _camera_rig.global_position.lerp(target, 1.0 - exp(-15.0 * delta))
	_camera_rig.rotation = Vector3(_pitch, _yaw, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if Net.is_server:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY, -1.2, 0.6)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and _connected:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------- Serveur

func _start_server() -> void:
	var err := Net.start_server()
	if err != OK:
		push_error("[serveur] impossible de démarrer : %s" % error_string(err))
		get_tree().quit(1)
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_running = true


func _on_peer_connected(id: int) -> void:
	print("[serveur] joueur %d connecté" % id)
	# Le nouveau venu reçoit d'abord les joueurs déjà présents.
	for other_id: int in players:
		spawn_player.rpc_id(id, other_id, players[other_id].global_position)
	var pos := _pick_spawn_point()
	_spawn(id, pos)
	spawn_player.rpc(id, pos)


func _on_peer_disconnected(id: int) -> void:
	print("[serveur] joueur %d déconnecté" % id)
	_despawn(id)
	despawn_player.rpc(id)


func _server_tick_step(delta: float) -> void:
	if not _running:
		return
	for p: Player in players.values():
		p.simulate(delta)
		if p.global_position.y < KILL_HEIGHT:
			p.global_position = _pick_spawn_point()
			p.velocity = Vector3.ZERO

	_tick += 1
	if _tick % SNAPSHOT_INTERVAL == 0 and not players.is_empty():
		var states := []
		for id: int in players:
			var p: Player = players[id]
			states.append([id, p.global_position, p.rotation.y])
		receive_snapshot.rpc(_tick, states)


func _pick_spawn_point() -> Vector3:
	var points := spawn_points.get_children()
	var point: Node3D = points[_next_spawn % points.size()]
	_next_spawn += 1
	return point.global_position


# ---------------------------------------------------------------- RPC

@rpc("any_peer", "call_remote", "unreliable_ordered")
func submit_input(move: Vector2, yaw: float, jump: bool) -> void:
	if not Net.is_server:
		return
	var p: Player = players.get(multiplayer.get_remote_sender_id())
	if p == null:
		return
	p.input_move = move.limit_length(1.0) # on ne fait jamais confiance au client
	p.input_yaw = wrapf(yaw, -PI, PI)
	p.input_jump = jump


@rpc("authority", "call_remote", "reliable")
func spawn_player(id: int, pos: Vector3) -> void:
	_spawn(id, pos)


@rpc("authority", "call_remote", "reliable")
func despawn_player(id: int) -> void:
	_despawn(id)


@rpc("authority", "call_remote", "unreliable_ordered")
func receive_snapshot(tick: int, states: Array) -> void:
	if not _has_snapshot or absf(tick - _server_tick) > Net.TICK_RATE * 0.5:
		_server_tick = tick
		_has_snapshot = true
	else:
		_server_tick = lerpf(_server_tick, tick, 0.1)

	for state: Array in states:
		var p: Player = players.get(state[0])
		if p:
			p.push_snapshot(tick, state[1], state[2])


# ---------------------------------------------------------------- Joueurs

func _spawn(id: int, pos: Vector3) -> void:
	if players.has(id):
		return
	var p: Player = PLAYER_SCENE.instantiate()
	p.name = str(id)
	p.peer_id = id
	p.is_local = not Net.is_server and id == multiplayer.get_unique_id()
	p.position = pos
	players_root.add_child(p)
	players[id] = p


func _despawn(id: int) -> void:
	var p: Player = players.get(id)
	if p:
		p.queue_free()
		players.erase(id)


func _clear_players() -> void:
	for id: int in players.keys():
		_despawn(id)


# ---------------------------------------------------------------- Client

func _send_input() -> void:
	var move := Vector2.ZERO
	var jump := false
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		move = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		jump = Input.is_action_pressed("jump")
	submit_input.rpc_id(1, move, _yaw, jump)


func _on_join_pressed(address: String) -> void:
	var err := Net.join(address.strip_edges())
	if err != OK:
		_status.text = "Erreur : %s" % error_string(err)
		return
	_status.text = "Connexion…"
	_join_button.disabled = true


func _on_connected() -> void:
	_connected = true
	_menu.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_connection_failed() -> void:
	_status.text = "Connexion impossible."
	_join_button.disabled = false


func _on_disconnected() -> void:
	_connected = false
	_has_snapshot = false
	_clear_players()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = "Déconnecté du serveur."
	_join_button.disabled = false
	_menu.show()


func _setup_input_map() -> void:
	# Touches physiques : la position WASD d'un clavier QWERTY = ZQSD sur un AZERTY.
	var bindings := {
		"move_forward": KEY_W,
		"move_back": KEY_S,
		"move_left": KEY_A,
		"move_right": KEY_D,
		"jump": KEY_SPACE,
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var ev := InputEventKey.new()
		ev.physical_keycode = bindings[action]
		InputMap.action_add_event(action, ev)


func _build_camera() -> void:
	_camera_rig = Node3D.new()
	_camera_rig.position = Vector3(0.0, 3.0, 0.0)
	add_child(_camera_rig)

	var arm := SpringArm3D.new()
	arm.spring_length = 5.0
	arm.collision_mask = 1 # le décor seulement, pas les joueurs (couche 2)
	arm.margin = 0.2
	_camera_rig.add_child(arm)

	var cam := Camera3D.new()
	arm.add_child(cam)
	cam.current = true


func _build_menu() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	_menu = center

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)

	var title := Label.new()
	title.text = "ARENA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	box.add_child(title)

	var address := LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "adresse du serveur (hote:port)"
	address.custom_minimum_size.x = 280
	box.add_child(address)

	_join_button = Button.new()
	_join_button.text = "Rejoindre"
	_join_button.pressed.connect(func() -> void: _on_join_pressed(address.text))
	address.text_submitted.connect(_on_join_pressed)
	box.add_child(_join_button)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
