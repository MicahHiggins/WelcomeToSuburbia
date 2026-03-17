extends ColorRect


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mask_1()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _draw():
	for i in range(20):
		var x_pos = i * 20  # Space them out by 20 pixels each
		var start_point = Vector2(x_pos, 20)
		var end_point = Vector2(x_pos, 100)
		draw_line(start_point, end_point, Color.RED, 2.0)
		

func mask_1():
	queue_redraw()
