## Fixture test for one inland assault at Omaha: can 42 American infantry take a
## single complete 11-man German strongpoint (sector 3) with unchanged health and ammunition?
##
## Method: everything is parked (staged, collisions off) except the 42 attackers
## placed in a block 28 m in front of the sector anchor, and the sector's non-town
## defenders. The test drives the simulation by hand for up to 150 simulated seconds
## (think() about three times a second, projectiles, tracers, flashes and effects
## every tick), logging a snapshot every 30 s into reviews/omaha/inland-assault.json,
## and stops early when no defender is left. Pass = every defender dead (report.success).
## Why: it checks the assault AI's staged plan (assault_goal), the bunker design and weapon balance
## without the landing, wire and village muddying the result.
## Run: godot --headless --path <repo> --script res://tests/omaha_assault.gd   (exit 0 = success)
extends SceneTree

## The Omaha battle controller.
var g

## The 42 attacking soldiers.
var attack=[]

## The sector's defenders.
var defend=[]

## Snapshot records written to the report.
var results=[]

## SceneTree entry point; defers to run().
func _initialize():call_deferred("run")

## Builds the fixture, runs the simulation loop and writes the report; quits with 0 if all defenders died, else 1.
func run():
	set_meta("battle_test",true)
	set_meta("battle_seed",19440606)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.phase="playing"
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	g.player.truck=null

	# The player is parked far away and invisible to AI so the result depends only on the AI-vs-AI fight.
	g.player.position=Vector3(1100,80,0)
	g.player.collision_layer=0

	# Park everyone first (staged, no collision, no physics); the loop below re-enables only the fixture soldiers.
	for a in g.actors:
		a.staged=true
		a.set_physics_process(false)
		a.collision_layer=0
		a.equipment.collision_layer=0
	var center=g.world.anchors[3]
	for a in g.friendlies:
		if a.boat!=null or attack.size()>=42:continue
		a.truck=null
		a.staged=false
		a.position=g.world.on_ground(center+Vector3((attack.size()%7-3)*2.0,0,28+int(attack.size()/7)*1.7))
		a.sector=3
		a.lane=center.x
		a.home=a.position

		# Stage 0 = start of the staged assault plan (see assault_goal in battle.gd).
		a.assault_stage=0
		a.collision_layer=8
		a.equipment.collision_layer=16
		a.set_physics_process(true)
		attack.append(a)
	for e in g.enemies:
		if e.sector!=3 or e.role=="town_guard":continue
		e.staged=false
		e.collision_layer=4
		e.equipment.collision_layer=16
		e.set_physics_process(true)
		defend.append(e)
	g.elapsed=500
	g.rebuild_spatial()

	# Fixed 150 simulated seconds; the battle controller's own step is disabled, so this loop advances time and every system by hand.
	for tick in range(150*Engine.physics_ticks_per_second):
		await physics_frame
		g.elapsed+=1.0/Engine.physics_ticks_per_second

		# AI decisions about three times a second, like the live game's budgeted thinking.
		if tick%maxi(1,Engine.physics_ticks_per_second/3)==0:
			g.rebuild_spatial()
			for a in attack+defend:
				if a.alive:a.think(g.elapsed)
		g.step_projectiles(1.0/Engine.physics_ticks_per_second)
		g.update_tracers(1.0/Engine.physics_ticks_per_second)
		g.update_flashes()
		for effect in g.effects.duplicate():
			effect.time-=1.0/Engine.physics_ticks_per_second
			if effect.time<=0:
				effect.node.queue_free()
				g.effects.erase(effect)
		if tick%(30*Engine.physics_ticks_per_second)==0:
			var states={}
			for a in attack:
				if a.alive:states[str(a.assault_stage)]=int(states.get(str(a.assault_stage),0))+1
			var record={"seconds":tick/Engine.physics_ticks_per_second,"attackers":attack.filter(func(a):return a.alive).size(),"defenders":defend.filter(func(a):return a.alive).size(),"stages":states,"grenades":g.grenade_detonations}
			results.append(record)
			print("ASSAULT ",JSON.stringify(record))

		# Stop once the strongpoint is cleared.
		if defend.all(func(e):return not e.alive):break
	var remaining=defend.filter(func(e):return e.alive)
	var survivors=attack.filter(func(a):return a.alive)
	var report={"fixture":"42 infantry starting behind wire vs one complete 11-man strongpoint; unchanged health/ammo", "snapshots":results,"survivors":survivors.size(),"remaining_defenders":remaining.map(func(a):return {"index":a.index,"role":a.role,"health":a.health,"position":str(a.position)}),"soldiers":survivors.map(func(a):return {"index":a.index,"stage":a.assault_stage,"position":str(a.position),"state":a.state,"ammo":a.rounds+a.reserve}),"success":remaining.is_empty()}
	var file=FileAccess.open("res://reviews/omaha/inland-assault.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("ASSAULT_RESULT ",JSON.stringify(report))
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit(0 if report.success else 1)
