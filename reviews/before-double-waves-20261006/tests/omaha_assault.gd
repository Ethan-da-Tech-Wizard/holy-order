# ==============================================================================
# Program: omaha_assault.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for omaha_assault.gd.
# ==============================================================================
## Fixture test for the Omaha inland assault: 42 attackers against one complete strongpoint.
##
## Sets up 42 friendly infantry in front of sector 3 and activates only that sector's defenders
## (no town guards), then simulates up to 150 s by calling the AI and projectile code by hand with
## a fixed time step. Samples every 30 s (attackers and defenders alive, assault stages,
## grenades) and writes reviews/omaha/inland-assault.json. Exit code 0 only when the report's
## `success` flag is true. Health and ammunition are unchanged from the real game.
## Run: `godot --headless --path . --script res://tests/omaha_assault.gd`.
extends SceneTree

# Mission instance.
var g

# Attackers and defenders taking part, and the periodic snapshots.
var attack=[]
var defend=[]
var results=[]
func _initialize():call_deferred("run")

# Test flags: deterministic seed 19440606 (the D-Day date).
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	# Uncapped frame rate so the headless run finishes as quickly as possible.
	Engine.max_fps=0
	await physics_frame
	# The test advances the simulation manually, so the mission's own physics processing is off.
	g.phase="playing"
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	# Park the player far away and out of collisions: the observer must not influence the battle.
	g.player.truck=null
	g.player.position=Vector3(1100,80,0)
	g.player.collision_layer=0
	# Put every actor in a dormant (staged) state first; only the chosen ones are woken below.
	for a in g.actors:
		a.staged=true
		a.set_physics_process(false)
		a.collision_layer=0
		a.equipment.collision_layer=0
	# Strongpoint 3 anchor: attackers line up 28 m in front of it in rows of 7, 1.7 m apart.
	var center=g.world.anchors[3]
	for a in g.friendlies:
		# Skip soldiers still in boats; stop at 42 attackers.
		if a.boat!=null or attack.size()>=42:continue
		a.truck=null
		a.staged=false
		a.position=g.world.on_ground(center+Vector3((attack.size()%7-3)*2.0,0,28+int(attack.size()/7)*1.7))
		a.sector=3
		# Reset their AI state so they start the approach from the beginning.
		a.lane=center.x
		a.home=a.position
		a.assault_stage=0
		# Collision layers 8 (friendly) and 16 (equipment) match the game's normal setup.
		a.collision_layer=8
		a.equipment.collision_layer=16
		a.set_physics_process(true)
		attack.append(a)
	# Defenders: all of sector 3's soldiers except the town guards, on layer 4 (enemies).
	for e in g.enemies:
		if e.sector!=3 or e.role=="town_guard":continue
		e.staged=false
		e.collision_layer=4
		e.equipment.collision_layer=16
		e.set_physics_process(true)
		defend.append(e)
	# Start far enough into the scenario clock that time-based triggers (e.g. the second wave) are inert.
	g.elapsed=500
	g.rebuild_spatial()
	# Simulate 150 s of fixed time steps.
	for tick in range(150*Engine.physics_ticks_per_second):
		await physics_frame
		g.elapsed+=1.0/Engine.physics_ticks_per_second
		# AI thinking at 3 Hz (every third of a second), like the game, to keep the run fast.
		if tick%maxi(1,Engine.physics_ticks_per_second/3)==0:
			g.rebuild_spatial()
			for a in attack+defend:
				if a.alive:a.think(g.elapsed)
		# Advance projectiles, tracers, muzzle flashes and effect timers by hand.
		g.step_projectiles(1.0/Engine.physics_ticks_per_second)
		g.update_tracers(1.0/Engine.physics_ticks_per_second)
		g.update_flashes()
		for effect in g.effects.duplicate():
			effect.time-=1.0/Engine.physics_ticks_per_second
			if effect.time<=0:
				effect.node.queue_free()
				g.effects.erase(effect)
		# Every 30 s, record counts of attackers/defenders alive and the assault stage distribution.
		if tick%(30*Engine.physics_ticks_per_second)==0:
			var states={}
			for a in attack:
				if a.alive:states[str(a.assault_stage)]=int(states.get(str(a.assault_stage),0))+1
			var record={"seconds":tick/Engine.physics_ticks_per_second,"attackers":attack.filter(func(a):return a.alive).size(),"defenders":defend.filter(func(a):return a.alive).size(),"stages":states,"grenades":g.grenade_detonations}
			results.append(record)
			print("ASSAULT ",JSON.stringify(record))
		# Stop early when all defenders are dead.
		if defend.all(func(e):return not e.alive):break
	# Final report: survivors, remaining defenders and the fixture description.
	var remaining=defend.filter(func(e):return e.alive)
	var survivors=attack.filter(func(a):return a.alive)
	var report={"fixture":"42 infantry starting behind wire vs one complete 11-man strongpoint; unchanged health/ammo", "snapshots":results,"survivors":survivors.size(),"remaining_defenders":remaining.map(func(a):return {"index":a.index,"role":a.role,"health":a.health,"position":str(a.position)}),"soldiers":survivors.map(func(a):return {"index":a.index,"stage":a.assault_stage,"position":str(a.position),"state":a.state,"ammo":a.rounds+a.reserve}),"success":remaining.is_empty()}
	var file=FileAccess.open("res://reviews/omaha/inland-assault.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("ASSAULT_RESULT ",JSON.stringify(report))
	# Shut down cleanly and return the success flag as the exit code.
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit(0 if report.success else 1)
