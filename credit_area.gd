extends Area3D
class_name EndCreditsTrigger

@export var credits_scroller_path: NodePath = NodePath("../CreditsScroller")
@export var one_shot: bool = true
@export var require_server: bool = true
@export var require_player_group: StringName = &"player"

var _fired := false

func _ready() -> void:
	monitoring = true
	monitorable = true
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	print("[CreditsTrigger] body_entered:", body.name)

	if _fired and one_shot:
		return

	if require_player_group != StringName() and not body.is_in_group(String(require_player_group)):
		print("[CreditsTrigger] not in player group")
		return

	if require_server and multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		print("[CreditsTrigger] not server, ignoring")
		return

	_fired = true

	if multiplayer.has_multiplayer_peer():
		print("[CreditsTrigger] broadcasting credits to all peers")
		rpc("_rpc_play_all")
	else:
		_play_local()

@rpc("any_peer", "call_local", "reliable")
func _rpc_play_all() -> void:
	_play_local()

func _play_local() -> void:
	var scroller := get_node_or_null(credits_scroller_path) as Node
	if scroller == null:
		push_warning("[CreditsTrigger] CreditsScroller not found at: " + String(credits_scroller_path))
		return

	print("[CreditsTrigger] found scroller:", scroller.name, " parent:", (scroller.get_parent() if scroller else null))

	# call deferred so it runs after the scene settles for this peer
	scroller.call_deferred("play")
