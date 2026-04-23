extends Control
@onready var timer: Timer = $"../Timer"
@onready var label: Label = $Label



func _process(delta: float) -> void:
	
	
	
	label.text = "Time Left: " + str(round(timer.time_left))






func _on_toy_piano_timer_start() -> void:
	print("ON/")
	timer.start()
