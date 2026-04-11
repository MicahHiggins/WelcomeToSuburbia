extends VBoxContainer
@onready var objectives: Label = $Objectives
@onready var main: Label = $main
@onready var side: Label = $side
@onready var curr_obj: VBoxContainer = $"."



var prev_text_main := ""
var curr_text_main := ""
var prev_text_side := ""
var curr_text_side := ""
var objToggle := false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(iterationChange)
	questHub.questTalk.connect(talkedTo)
	questHub.isaacQuest.connect(isaacTrigger)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	#FIDO FOUND!
	if objToggle == true:
		side.text =  "Tell the Campbell Family you found Fido!"
	


#checks if campbells are talked to during iteration 3-5
func talkedTo(value: int):
	if value >= 2 && value <= 5:
		if questHub.dogFound == true:
			side.text = "Tell Campbells you have found Fido"
		else:
			side.text = "Find Fido (The Dog)"

#Iteration change (ref questHub.gd)
func iterationChange(value: int):
	if value == 1:
		main.text = main.text + "\n Talk to Issac (corner)"
		
	if value == 2:
		#main.text = main.text + "\n Talk to Issac (corner)"
		side.text = "Investigate the Crying (Campbells)"

func isaacTrigger(value: int):
	if value >= 5:
		pass
		
