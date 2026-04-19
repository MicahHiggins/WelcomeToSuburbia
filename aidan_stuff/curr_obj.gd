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

var isaacQuestDB := false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	questHub.iteration_changed.connect(iterationChange)
	questHub.campbellQuest.connect(campbellProgression)
	questHub.isaacQuest.connect(isaacTrigger)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	#FIDO FOUND!
	if objToggle == true:
		side.text =  "Tell the Campbell Family\n you found Fido!"
	


#checks if campbells are talked to during iteration 3-5
func campbellProgression(value: int):
	if value >= 2 && value <= 5 && questHub.campbellProg == 0:
		if questHub.campbellProg == 4:
			side.text = "Tell Campbells you have found Fido"
			#questHub.campbellProg = 4
	if questHub.campbellProg == 1:
			side.text = "Find Fido (The Dog)"
	if questHub.campbellProg == 2:
		side.text =  "Tell the Campbell Family\n you found Fido!"
	if value == 2 && questHub.campbellProg == 0:
		side.text = "Investigate the Crying\n (Campbells)"
	if questHub.campbellProg == 3:
		side.text = "none"

#Iteration change (ref questHub.gd)
func iterationChange(value: int):
	
	if value == 2 && questHub.campbellProg == 0:
		side.text = "Investigate the Crying\n (Campbells)"
	
	if value == 1 && isaacQuestDB == false:
		isaacQuestDB = true
		print("UI Debugging...")
		prev_text_main = "Find Your Home (130)"
		main.text = main.text + "\n Talk to Issac (corner)"
		


func isaacTrigger(value: int):
	#print("Is issac UI ON?")
	print("FROM UI: iss quest", GlobalVariables.isaac_quest_progression)
	if GlobalVariables.isaac_quest_progression == 1:
		print("ISAAC HAS ENTERED THE UI!")
		
		main.text = prev_text_main + "\n explore the\n neighborhood"
		#GlobalVariables.isaac_quest_progression = 2
		
	if GlobalVariables.isaac_quest_progression == 2:
		main.text = prev_text_main + "\n investigate around 114..."
		
	elif GlobalVariables.isaac_quest_progression == 3:
		main.text = prev_text_main + "\n Tell Isaac What You\n Found"
		
	if GlobalVariables.isaac_quest_progression == 4:
		main.text = "Find Your Home (130)\n break into house 114"
		
