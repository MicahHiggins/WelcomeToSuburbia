extends Area3D
var toggle_detection
@onready var timer: Timer = $Timer


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	timer.wait_time = 30
	toggle_detection = true

#Little mech for 1st iteration! Placeholder/debugging
	
func my_timed_function():
	print("IterationDQ1")
	#GlobalVariables.iterations += 1
	#GlobalVariables.gameStart.emit()
	questHub.it_change()
	queue_free()
	#Might use for differnt ints!
	#timer.wait_time = 1000
	#timer.start()






#
#func _on_timer_timeout() -> void:
	#toggle_detection = true
	
	


func _on_body_entered(body: Node3D) -> void:
	#print("WHAT THE FUCK")
	if body.is_in_group("player"):
		
		if toggle_detection == true:
			toggle_detection = false
			print("Before Iter1: ", GlobalVariables.iterations)
			
			my_timed_function()
			
			print("After Iter2 ", GlobalVariables.iterations)
		
		
