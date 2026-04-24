extends VBoxContainer
@onready var objectives: Label = $Objectives
@onready var main: Label = $main
@onready var side: Label = $side
@onready var curr_obj: VBoxContainer = $"."
@onready var quest_update: AudioStreamPlayer = $"../Sounds/QuestUpdate"
@onready var page_flip: AudioStreamPlayer = $"../Sounds/PageFlip"
@onready var page_flip_2: AudioStreamPlayer = $"../Sounds/PageFlip2"
@onready var update: Label = $"../update"



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
	update.visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	#FIDO FOUND!
	if objToggle == true:
		side.text =  "Tell Mr. Campbell\n you found Fido!"
	
func questUpdateThingy():
	update.visible = true
	await get_tree().create_timer(4.0).timeout
	update.visible = false

#checks if campbells are talked to during iteration 3-5
func campbellProgression(value: int):
	if value >= 2 && value <= 5 && questHub.campbellProg == 0:
		if questHub.campbellProg == 4:
			side.text = "Tell Mr. Campbell\n you found Fido!"
			#questHub.campbellProg = 4
	if questHub.campbellProg == 1:
			side.text = "Find Fido (The Dog)\n for Mr. Campbell"
	if questHub.campbellProg == 2:
		side.text =  "Tell Mr. Campbell\n you found Fido!"
	if value == 2 && questHub.campbellProg == 0:
		side.text = "Investigate the Crying\n (Campbells)"
	if questHub.campbellProg == 3:
		side.text = "none"
	quest_update.play()
	questUpdateThingy()
	

#Iteration change (ref questHub.gd)
func iterationChange(value: int):
	
	if value == 2 && questHub.campbellProg == 0:
		side.text = "Investigate the Crying\n (Mr. Campbell)"
		quest_update.play()
		questUpdateThingy()
	
	if value == 1 && isaacQuestDB == false:
		isaacQuestDB = true
		print("UI Debugging...")
		prev_text_main = "Find Home"
		main.text = main.text + "\n Talk to Issac (corner)"
		quest_update.play()
		questUpdateThingy()
		


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
		main.text = "break into house 114"
		
	quest_update.play()
	questUpdateThingy()
