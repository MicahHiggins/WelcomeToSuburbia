extends Node2D



var click_position: Array = []


func _input(event: InputEvent) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
		
	click_position.append(event.position)
	print(event.position)
	queue_redraw()
	
#
#
#func _ready() -> void:
	#draw_circle(Vector2(100, 100), 10, Color.RED, true, 1, false)
	#

func _draw() -> void:
	for point in click_position:
		draw_circle(point, 10, Color.RED)
		#print("TESTTSE")
