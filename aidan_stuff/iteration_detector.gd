extends Area3D
var toggle_detection
@onready var timer: Timer = $Timer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	toggle_detection = true


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
	
func my_timed_function():
	#print("TESTSTEST")
	timer.wait_time = 60
	timer.start()







func _on_timer_timeout() -> void:
	toggle_detection = true
	


func _on_body_entered(body: Node3D) -> void:
	#print("TSTTST")
	if toggle_detection == true:
		print(GlobalVariables.iterations)
		my_timed_function()
		GlobalVariables.iterations = GlobalVariables.iterations + 1
		toggle_detection = false
		
