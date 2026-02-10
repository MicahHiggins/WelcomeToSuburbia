extends Node
class_name NPCStateMachine

@export var initial_state_name: StringName = &"PatrolState"
@export var initial_state : NPCState

var npc: CharacterBody3D
var current: NPCState = null
#From Aidan's State Machine
var states : Dictionary = {}

func _ready() -> void:
	npc = get_parent() as CharacterBody3D
	if npc == null:
		push_error("NPCStateMachine must be a child of the NPC.")
		return

	# Inject references into all child states
	for c in get_children():
		var st := c as NPCState
		if st == null:
			continue
		st.npc = npc
		st.sm = self

	print("[NPCStateMachine] ready on:", npc.name, " children:", get_child_count())
	change_state(initial_state_name)
	
	for child in get_children():
		if child is NPCState:
			states[child.name] = child
			child.change_state.connect(change_state)
			child.npc = get_parent()
			child.initialize()
	if initial_state:
		initial_state.enter()
		current = initial_state

func change_state(state_name: StringName, msg := {}) -> void:
	var next := get_node_or_null(String(state_name)) as NPCState
	if next == null:
		push_error("[NPCStateMachine] State not found: " + String(state_name))
		return

	if current != null:
		current.exit()

	current = next
	print("[NPCStateMachine] -> ", String(state_name))
	current.enter(msg)

# NPC.gd calls this
func physics_update(delta: float) -> void:
	if current != null:
		current.physics_update(delta)
		
