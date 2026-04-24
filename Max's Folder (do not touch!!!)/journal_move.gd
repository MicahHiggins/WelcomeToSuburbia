extends Control
@onready var animation_player: AnimationPlayer = $AnimationPlayer



func _ready() -> void:
	animation_player.play("moveBack")
	
	



func _input(event: InputEvent) -> void:
	if event.is_action_pressed("journal"):
		animation_player.play("moveJournal")
	if event.is_action_released("journal"):
		animation_player.play("moveBack")
		
		
	
