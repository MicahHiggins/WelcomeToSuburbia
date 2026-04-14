extends Node2D
# No need for class_name if it's an Autoload, but you can keep it.

signal iteration_changed(value: int)
signal questTalk(value: int)
signal isaacQuest(value: int)
signal campbellQuest(value: int)

var campbellProg := 0
var dogFound := false

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

# Do the same for your triggers
func campbellTrigger():
	sync_campbell.rpc(GlobalVariables.iterations)

@rpc("authority", "call_local", "reliable")
func sync_campbell(val):
	campbellQuest.emit(val)

func isaacTrigger():
	print("ISsaccTriggers")
	GlobalVariables.isaac_quest_progression += 1
	sync_isaac.rpc(GlobalVariables.iterations)
	

@rpc("authority", "call_local", "reliable")
func sync_isaac(val):
	isaacQuest.emit(val)
