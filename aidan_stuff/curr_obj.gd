extends VBoxContainer
@onready var objectives: Label = $Objectives

@onready var curr_obj: VBoxContainer = $"."
var prev_text := ""
var curr_text := ""
var objToggle := false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(iterationChange)
	questHub.questTalk.connect(talkedTo)
	questHub.isaacQuest.connect(isaacTrigger)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if objToggle == true:
		objectives.text = prev_text + "\n tell Campbells you found Fido"
	


#checks if campbells are talked to during iteration 3-5
func talkedTo(value: int):
	if value >= 2 && value <= 5:
		print("Campbells talked detected!")
		
		
		objectives.text = prev_text + "\n Find Fido (The Dog)"

#Iteration change (ref questHub.gd)
func iterationChange(value: int):
	if value == 2:
		prev_text = objectives.text #gets prev text
		
		objectives.text = objectives.text + "\n Investigate the Crying (Campbells)"

func isaacTrigger(value: int):
	if value >= 5:
		pass
		
