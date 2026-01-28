extends CanvasLayer

@onready var item1: Label = $Item1Label
@onready var item2: Label = $Item2Lable

var player: CharacterBody3D

func _ready() -> void:
	player = get_parent() as CharacterBody3D

	# UI should only be visible & updating for the locally controlled player.
	if player == null or not player.is_multiplayer_authority():
		visible = false
		set_process(false)
		set_physics_process(false)
		return

	visible = true
	_update_labels()

func _process(_delta: float) -> void:
	_update_labels()

func _update_labels() -> void:
	if player == null:
		return

	var inv: Array[StringName] = player.inventory

	item1.text = ""
	item2.text = ""

	if inv.size() >= 1:
		item1.text = String(inv[0])
	if inv.size() >= 2:
		item2.text = String(inv[1])
