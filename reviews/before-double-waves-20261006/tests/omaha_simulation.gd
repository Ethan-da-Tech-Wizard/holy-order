# ==============================================================================
# Program: omaha_simulation.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for omaha_simulation.gd.
# ==============================================================================
## Long-run AI simulation of the Omaha battle with periodic snapshots.
##
## Plays up to 600 s of the mission with the player parked out of the way, taking a snapshot at
## fixed times (45, 65, 90, ... 600 s): counts of allies and enemies alive, shots fired, boat
## penetrations, breaches, soldier states, stuck soldiers, how many crossed the wire, and so on.
## Writes reviews/omaha/simulation-progress.json after every snapshot and
## reviews/omaha/simulation.json at the end (with step-time percentiles). Environment: OMAHA_SIM_END
## stops the run at the given second. It asserts nothing; a person or script reads the numbers.
extends SceneTree

# Mission instance.
var g

# Collected snapshots, the sample times and the per-step durations in ms.
var snapshots=[]
var sample_times=[]
var durations=[]
func _initialize():call_deferred("run")

## Record the current battle state.
func snapshot():
	var states={}
	var positions=[]
	var living=0
	var stuck=0
	var engineers=0
	var spread=[]
	var crossed=0
	# Only soldiers who are alive, on foot (not in a boat) and active (not staged) are counted.
	for a in g.friendlies:
		if not a.alive or a.boat!=null or a.staged:continue
		living+=1
		states[a.state]=int(states.get(a.state,0))+1
		# A soldier stuck for more than 0.5 s counts as stuck.
		if a.stuck>0.5:stuck+=1
		# Count engineers carrying Bangalore torpedoes (wire breaching charges).
		if a.bangalores>0:engineers+=1
		if a.truck==null:
			# z and x spread of the infantry; crossing means past the last wire row by 2 m.
			positions.append(a.position.z)
			spread.append(a.position.x)
			if a.position.z<g.Layout.WIRE_ROWS[2]-2:crossed+=1
	# Sorted so percentiles can be read out of the lists.
	positions.sort()
	spread.sort()
	var record={"time":snappedf(g.elapsed,0.1),"allies":g.allies_alive,"enemies":g.germans_alive,"shots":g.ammo_spent,"vehicle_shots":g.vehicle_shots,"penetrations":g.boat_penetrations,"breaches":g.breaches,"grenades":g.grenade_detonations,"secured":g.secured,"town":g.town_control,"states":states,"foot_soldiers":positions.size(),"past_all_wire":crossed,"width_90_percent":spread[int(spread.size()*0.95)]-spread[int(spread.size()*0.05)] if spread.size()>1 else 0,"front_z":positions[0] if not positions.is_empty() else 0,"median_z":positions[int(positions.size()/2)] if not positions.is_empty() else 0,"stuck":stuck,"engineers":engineers,"shots_at_player":g.shots_at_player,"shots_at_ai":g.shots_at_ai,"departed":g.boats.filter(func(b):return b.departed).size(),"friendly_deaths":g.friendly_death_causes.duplicate()}
	snapshots.append(record)
	print("SNAPSHOT ",JSON.stringify(record))
	# Rewrite the progress file after every snapshot so partial results survive a crash.
	var file=FileAccess.open("res://reviews/omaha/simulation-progress.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(snapshots,"  "))

## Run the simulation.
func run():
	set_meta("battle_test",true)
	# Deterministic seed 19440606.
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.begin()
	# Observe without an unattended player death aborting the AI battle.
	# No team health/ammo buffs: observer is moved away after disembarkation.
	# Observe without an unattended player death aborting the AI battle.
	# No team health/ammo buffs: observer is moved away after disembarkation.
	g.player.set_physics_process(false)
	g.player.collision_layer=0
	# Snapshot times in simulated seconds.
	var targets=[45,65,90,120,180,240,275,300,360,480,600]
	# Optionally shorten the run for quick checks.
	if OS.has_environment("OMAHA_SIM_END"):
		targets=targets.filter(func(t):return t<=int(OS.get_environment("OMAHA_SIM_END")))
	var index=0
	var last=Time.get_ticks_usec()
	# Run until the last snapshot time.
	while g.elapsed<targets.back()+0.1:
		await physics_frame
		# Once the player leaves the boat, move him far away so he cannot affect or be killed in the battle.
		if g.player.truck==null:g.player.position=Vector3(1100,80,0)
		var now=Time.get_ticks_usec()
		durations.append((now-last)/1000.0)
		last=now
		# Take a snapshot when its time arrives.
		if g.elapsed>=targets[index]:
			snapshot()
			index+=1
			if index>=targets.size():break
		# Keep the game in play phase.
		if g.phase!="playing":g.phase="playing"
	# Final summary with step-time percentiles.
	durations.sort()
	var result={"seed":19440606,"mode":"headless simulation, not GPU FPS","snapshots":snapshots,"median_step_ms":durations[int(durations.size()*0.5)],"p95_step_ms":durations[int(durations.size()*0.95)],"p99_step_ms":durations[int(durations.size()*0.99)]}
	var file=FileAccess.open("res://reviews/omaha/simulation.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	print("RESULT ",JSON.stringify(result))
	# Shut down cleanly.
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit()
