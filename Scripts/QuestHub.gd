extends Node2D

class_name questHub


signal iterationManipulation(value: int)
signal questManipulation(value: int)
signal isaacStuff(value: int)


 # Global signal
static var singleton := questHub.new()
static var iteration_changed := Signal(singleton, "iterationManipulation")
static var questTalk := Signal(singleton, "questManipulation")
static var isaacQuest := Signal(singleton, "isaacStuff")


static var dogFound := false
#func set_value(new_value: int) -> void:
	## ... update state ...
	#iteration_changed.emit(GlobalVariables.iterations)
	#
	
#can call this function anywhere for it to be triggered
static func it_change():
	print("Iteration Change Detected!?: ")
	print(GlobalVariables.iterations)
	iteration_changed.emit(GlobalVariables.iterations)

static func campbellTalk():
	#print("Iteration Change Detected!?: ")
	#print(GlobalVariables.iterations)
	questTalk.emit(GlobalVariables.iterations)
	
static func isaacTrigger():
	print("Iteration Change Detected!?: ")
	print(GlobalVariables.iterations)
	isaacQuest.emit(GlobalVariables.iterations)


#Ok lets do this

#First Iteration:
#UI marker - "Find Home (130)"
#Abigal: Greets and welcomes player
#Campbell: Greets and Welcomes player (w/ dog)
#Bob: Greets the Player
#house 104 HOA: stares
#Issac: silence
#Trigger: Going into the next iteration via collision (timer 60 seconds)
 

#2nd Iteration
#UI marker - "Find Home (130)"
#Abigal: Dialogue Change
#Campbell: Greets and Welcomes player (w/ dog)
#Bob: Greets the Player
#house 104 HOA: stares
#Issac: silence
#Pass 124 with heartbeat loud and cool visuals


#3rd Iteration
#Abigail warns the player, and vaguely refers to the dog quest
#Campbells: Find dog quest (w/ no dog)
#Bob begins to worry
#house 104 HOA: stares w/ 2 people
#Spawn dog in different (maybe random location?)
#Baby Crying triggers (UI - "Investigate tHe Crying")
#next iteration: talk to isaac?

#4th Iteration
#Abigail updates the player
#Campbell Dog quest open
#Bob can really worry
#Issac silence


#5th Iteration
#Abigial HOA reveal, tells the player what's coming
#Campbell Outcome:
	#if player found and told campbell about dog befre they talk on 5th iteration
		#bus = false
	#else
		#bus = true

#Campbells outcome plays (either bus or dog eating them) + trigger for next iteration.

#6th iteration
#Isaac: if baby crying, eats
		#else: stays silent
#Bob audio cue to talk and advance to phase 2 (UI = "Investigate 104") (ONLY CUE TO ADVANCE)
#if Bob audio cue, when both players get to 104, cutscene for phase 2
	
	
