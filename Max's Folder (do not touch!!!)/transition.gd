extends Area3D

@onready var quest_marker_: Node = $"QuestMarker!"
@onready var collision_shape_3d: CollisionShape3D = $CollisionShape3D

@export var level_index_to_load: int = 2
@export var level_flow_group: StringName = &"level_flow_manager"
@export var marker_animplayer_path: NodePath = NodePath("QuestMarker!/AnimationPlayer")
@export var marker_anim_name: StringName = &"Activate"

var _used: bool = false

func _ready() -> void:
	questHub.isaacQuest.connect(isaacTrigger)

	if quest_marker_ != null:
		quest_marker_.visible = false

	collision_shape_3d.set_deferred("disabled", true)

	match GlobalVariables.isaac_quest_progression:
		4:
			if quest_marker_ != null:
				quest_marker_.visible = true
		_:
			if quest_marker_ != null:
				quest_marker_.visible = false

func isaacTrigger(_value: int) -> void:
	if GlobalVariables.isaac_quest_progression == 4:
		if quest_marker_ != null:
			quest_marker_.visible = true
		collision_shape_3d.set_deferred("disabled", false)

func _on_body_entered(body: Node3D) -> void:
	if _used:
		return
	if body == null or not body.is_in_group("player"):
		return

	_used = true
	print("SUCCESS!!!! switching to level ", level_index_to_load)

	
	_try_play_marker_anim()

	# switch level via LevelFlowManager (server-authority if multiplayer)
	var lfm := _get_level_flow_manager()
	if lfm == null:
		push_error("Could not find LevelFlowManager. Make sure it's in group 'level_flow_manager'.")
		return

	lfm.request_level_change(level_index_to_load)

func _get_level_flow_manager() -> Node:
	# your LevelFlowManager already registers itself in group "level_flow_manager"
	var n := get_tree().get_first_node_in_group(String(level_flow_group))
	if n != null:
		return n

	# fallback: search current scene for the node name
	var scene := get_tree().current_scene
	if scene != null:
		var found := scene.find_child("LevelFlowManager", true, false)
		if found != null:
			return found

	return null

func _try_play_marker_anim() -> void:
	if marker_anim_name == &"":
		return
	var ap := get_node_or_null(marker_animplayer_path) as AnimationPlayer
	if ap == null:
		return
	var a := String(marker_anim_name)
	if ap.has_animation(a):
		ap.play(a)
