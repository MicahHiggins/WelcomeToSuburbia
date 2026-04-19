extends Node2D
# No need for class_name if it's an Autoload, but you can keep it.

signal iteration_changed(value: int)
#signal questTalk(value: int)
signal isaacQuest(value: int)
signal campbellQuest(value: int)

signal talkingNpc(value: int)

var campbellProg := 0
var found_fido_early := false




func audio_play_talk(value: int):
	talkingNpc.emit(0)
# This is the function you call from any other script
func it_change():
	# 1. If a client calls this, they ask the server to change it
	if not multiplayer.is_server():
		rpc_id(1, "request_it_change")
	else:
		# 2. If the server calls this (or receives the request), it executes
		request_it_change()

@rpc("any_peer", "call_local", "reliable")
func request_it_change():
	if not multiplayer.is_server(): return
	
	# 3. Server updates the value and tells EVERYONE to sync up
	# We send GlobalVariables.iterations + 1 as the new value
	
	sync_iteration.rpc(GlobalVariables.iterations + 1)

@rpc("authority", "call_local", "reliable")
func sync_iteration(new_value: int):
	print("Iteration Syncing for all players: ", new_value)
	GlobalVariables.iterations = new_value
	iteration_changed.emit(new_value)
	GlobalVariables.dialogueSignal.emit()

# Do the same for your triggers
# Inside questHub.gd

func campbellTrigger():
	# 1. If a client calls this, ask the server to update the progress
	if not multiplayer.is_server():
		rpc_id(1, "server_request_campbell_up")
	else:
		server_request_campbell_up()

@rpc("any_peer", "call_local", "reliable")
func server_request_campbell_up():
	if not multiplayer.is_server(): return
	
	# 2. Server performs the logic
	questHub.campbellProg += 1
	
	if found_fido_early == true:
		found_fido_early = false
		print("BRUH")
		questHub.campbellProg = 2
	
	# 3. Server broadcasts the NEW values to everyone
	sync_campbell_state.rpc(questHub.campbellProg, GlobalVariables.iterations)

@rpc("authority", "call_local", "reliable")
func sync_campbell_state(new_prog: int, iter_val: int):
	# 4. Everyone updates their local variables to match the server
	questHub.campbellProg = new_prog
	
	# 5. Emit the signal so Dialogue/UI refreshes
	campbellQuest.emit(iter_val)
	print("Campbell Quest Synced! Progress is now: ", new_prog)
	
	# Inside questHub.gd

func isaacTrigger():
	# 1. If I'm a client, I ask the server to handle the progression
	if not multiplayer.is_server():
		rpc_id(1, "server_request_isaac_up")
	else:
		# 2. If I'm the server, I just run it
		server_request_isaac_up()

@rpc("any_peer", "call_local", "reliable")
func server_request_isaac_up():
	if not multiplayer.is_server(): return
	
	# 3. Server adds +1 to the GLOBAL state
	GlobalVariables.isaac_quest_progression += 1
	
	# 4. Server tells EVERYONE what the new number is
	# We pass BOTH the progression and the iterations to keep everything in sync
	sync_isaac_state.rpc(GlobalVariables.isaac_quest_progression, GlobalVariables.iterations)

@rpc("authority", "call_local", "reliable")
func sync_isaac_state(new_prog: int, iter_val: int):
	# 5. Every player updates their local variable to match the server
	GlobalVariables.isaac_quest_progression = new_prog
	
	# 6. Emit the signal so your Dialogue/UI knows to refresh
	isaacQuest.emit(iter_val)
	print("Isaac Quest Synced to: ", new_prog)
#
#func isaacTrigger():
	#print("ISsaccTriggers")
	#GlobalVariables.isaac_quest_progression += 1
	#sync_isaac.rpc(GlobalVariables.iterations)
	#
#
#@rpc("authority", "call_local", "reliable")
#func sync_isaac(val):
	#isaacQuest.emit(val)
