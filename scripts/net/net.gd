extends Node
## Connexion réseau (autoload "Net").
## Détecte si l'instance tourne en serveur dédié et gère la création du peer ENet.

signal connected
signal connection_failed
signal disconnected

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const TICK_RATE := 60

var is_server := false


func _ready() -> void:
	is_server = OS.has_feature("dedicated_server") \
		or DisplayServer.get_name() == "headless" \
		or _has_arg("--server")

	if is_server:
		# Sans rendu, rien ne limite la boucle principale : on évite de cramer un cœur du NAS.
		Engine.max_fps = TICK_RATE

	multiplayer.connected_to_server.connect(connected.emit)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func start_server() -> Error:
	var port := int(_arg_value("--port", str(DEFAULT_PORT)))
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	print("[serveur] en écoute sur le port %d (UDP), %d joueurs max" % [port, MAX_PLAYERS])
	return OK


## address : "ip", "nom.synology.me" ou "hote:port".
func join(address: String) -> Error:
	var host := address
	var port := DEFAULT_PORT
	if ":" in address:
		host = address.get_slice(":", 0)
		port = int(address.get_slice(":", 1))

	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(host, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	connection_failed.emit()


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	disconnected.emit()


func _args() -> PackedStringArray:
	return OS.get_cmdline_args() + OS.get_cmdline_user_args()


func _has_arg(arg_name: String) -> bool:
	return arg_name in _args()


func _arg_value(arg_name: String, default: String) -> String:
	for arg in _args():
		if arg.begins_with(arg_name + "="):
			return arg.get_slice("=", 1)
	return default
