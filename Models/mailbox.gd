extends Node3D
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var nextToMailbox := false
var mailboxOpen := false

var itemProduced := false
var baseball_bat
var flashlight
const FLASHLIGHT = preload("res://Assets/RandomObjects/flashlight/flashlight.tscn")
const BAT_CLEAN = preload("res://GameLevelsETC/Items/bat_clean.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	baseball_bat = BAT_CLEAN.instantiate()
	flashlight = FLASHLIGHT.instantiate()
	


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("interact") && nextToMailbox == true && mailboxOpen == false:
		animation_player.play("OpenMailbox")
		mailboxOpen = true
		#if itemProduced == false:
			#var ranNum = randi_range(1, 3)
			#
			#match(ranNum):
				#1: 
					#add_child(baseball_bat)
				#2: 
					#add_child(flashlight)
				#3:
					#pass
					
	elif Input.is_action_just_pressed("interact") && nextToMailbox == true && mailboxOpen == true:
		animation_player.play("CloseMailbox")
		mailboxOpen = false
	
		


func _on_area_3d_body_entered(body: Node3D) -> void:
	if body.is_multiplayer_authority():
		tutorial.interact = true
		nextToMailbox = true


func _on_area_3d_body_exited(body: Node3D) -> void:
	if body.is_multiplayer_authority():
		tutorial.interact = false
		nextToMailbox = false
