# ==============================================================================
# Program: ai_simulation.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Automated test script verifying runtime performance, physics stability, or behavior correctness for ai_simulation.gd.
# ==============================================================================
## Headless AI behaviour test for the desert mission.
##
## Loads scenes/main.tscn, keeps the player safe and passive, wakes the defenders with a
## gunshot, then samples every enemy for 12 x 150 ticks (at 3x time scale). It passes
## only if at least one "assault" defender moved more than 12 m from its start AND the machine
## gun nest was manned at some point. The full sample log is written to
## reviews/ai-simulation.json and the process exit code is 0 on success, 1 on failure.
## Run (SceneTree script): `godot --headless --path . --script res://tests/ai_simulation.gd`.
extends SceneTree

# The mission scene instance under test.
var g

# Defer run() so the scene tree is fully initialised before any await.
func _initialize():call_deferred("run")

## Wait `n` physics ticks.
func ticks(n):
	for i in range(n):await physics_frame
func run():
	# Build the mission and make it the current scene so scripts that use get_tree().current_scene work.
	g=load("res://scenes/main.tscn").instantiate()
	root.add_child(g)
	current_scene=g
	# Let the level finish its deferred setup (navigation graph, spawns) before starting.
	await ticks(60)
	# Skip the title/briefing flow and go straight to play.
	g.phase="playing"
	# Put the player at a fixed spot near the entrance, invulnerable and frozen, so the test observes only the AI.
	g.player.position=Vector3(0,0.04,20)
	g.player.health=100000
	g.player.set_physics_process(false)
	g.player.set_process(false)
	# Suppress the rifle pickup comment/quip which would otherwise pop up mid-test.
	g.pickup_played=true
	# Kill the first enemy (the sentry) so the test starts with the alarm raised by the gunshot, not his normal watch.
	g.enemies[0].take_damage(200)
	# Gunshot noise at the village edge: radius 175, team 1 (player), so defenders investigate.
	g.emit_noise(Vector3(0,1.5,26),175,1,"gunshot")
	# Remember where each remaining enemy started to detect advancing.
	var positions={}
	for e in g.enemies.slice(1):positions[e.index]=e.position
	var samples=[]
	# Run three times faster than real time so 1800 ticks finish quickly.
	Engine.time_scale=3
	var mg_occupied=false
	var digs=0
	# 12 sample cycles of 150 ticks; each logs every enemy's role, state, target and ammo.
	for cycle in range(12):
		await ticks(150)
		var actors=[]
		for e in g.enemies.slice(1):
			actors.append({"index":e.index,"role":e.role,"state":e.state,"position":str(e.position),"visible":e.visible_target,"shots":e.shots_fired,"rounds":e.rounds,"reserve":e.reserve_rounds,"destination":str(e.destination),"path_remaining":e.path.size()-e.path_cursor,"cover":e.has_cover,"dug":e.entrenched})
			if e.mounted:mg_occupied=true
			if e.entrenched:digs+=1
		samples.append(actors)
		print("AI_SAMPLE ",cycle," ",JSON.stringify(actors))
	# Assault soldiers must have travelled at least 12 m from their start position.
	var assault_moved=true
	for e in g.enemies:
		if e.role=="assault" and e.position.distance_to(positions[e.index])<12:assault_moved=false
	# Report both pass criteria plus extra facts (shots from the gun, whether anyone dug in).
	var report={"assault_advanced":assault_moved,"mg_manned":mg_occupied,"mg_shots":g.mg_nest.shots_fired,"defenders_dug":digs>0,"samples":samples}
	FileAccess.open("res://reviews/ai-simulation.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("AI_SIMULATION_COMPLETE ",assault_moved," MG ",mg_occupied," shots ",g.mg_nest.shots_fired," digging ",digs)
	# Return to the title phase and restore the time scale so shutdown is clean.
	g.phase="title"
	Engine.time_scale=1
	await ticks(4)
	# Exit code is the test result for scripts and CI.
	quit(0 if assault_moved and mg_occupied else 1)
