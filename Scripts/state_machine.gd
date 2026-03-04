extends Node
class_name NPCStateMachine

@export var initial_state_name: StringName = &"PatrolState"

var npc: CharacterBody3D
var current: NPCState = null

func _ready() -> void:
	npc = get_parent() as CharacterBody3D
	if npc == null:
		push_error("NPCStateMachine must be a child of the NPC.")
		return

	# Inject references + connect state requests exactly once
	for c in get_children():
		var st := c as NPCState
		if st == null:
			continue
		st.npc = npc
		st.sm = self
		if not st.change_state.is_connected(change_state):
			st.change_state.connect(change_state)
		st.initialize()

	#print("[NPCStateMachine] ready on:", npc.name, " children:", get_child_count())
	change_state(initial_state_name)

func change_state(state_name: StringName, msg := {}) -> void:
	# IMPORTANT: ignore repeats (stops spam)
	if current != null and current.name == String(state_name):
		return

	var next := get_node_or_null(String(state_name)) as NPCState
	if next == null:
		push_error("[NPCStateMachine] State not found: " + String(state_name))
		return

	if current != null:
		current.exit()

	current = next
	#print("[NPCStateMachine] -> ", String(state_name))
	current.enter(msg)

# NPC.gd calls this
func physics_update(delta: float) -> void:
	if current != null:
		current.physics_update(delta)
