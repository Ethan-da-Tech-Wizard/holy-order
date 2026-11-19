## Urban-combat fixture for the Omaha village: 240 Americans (plus the bazooka
## carriers) advance on the 150 town guards and three Panzer IVs with no help from the player.
##
## Method: everyone is parked; German beach defenders are removed; the attackers are laid out in a 24-wide grid at z = -338
## (just outside the village) with assault_stage 6 (the village phase of assault_goal), then the controller's loop is run
## manually (tanks, rocket teams, heavy projectiles, think about twice a second,
## bullets, effects) for TOWN_ASSAULT_SECONDS (default 180 s of simulated time).
## Every 30 s it records allies and enemies alive and tank health, finally writing
## reviews/omaha/town-assault.json. It reports; it does not fail on a threshold (exit 0).
## Why: it checks house routing, doorway fighting, building collapse, tank and bazooka behaviour
## under load without the landing.
## Run: godot --headless --path <repo> --script res://tests/omaha_town_assault.gd
extends SceneTree

## The Omaha battle controller.
var g

## The attacking soldiers.
var attack=[]

## Snapshot records.
var snapshots=[]

## SceneTree entry point; defers to run().
func _initialize():call_deferred("run")

## Builds the fixture, runs the simulation and writes the report.
func run():
	set_meta("battle_test",true)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	g.player.truck=null
	g.player.position=Vector3(900,80,0)
	g.player.collision_layer=0
	for a in g.actors:
		# Park every actor; the German beach garrison is then marked dead so only the village is contested.
		a.set_reserve(true)
		a.set_physics_process(false)
		if a.team==0 and a.role!="town_guard":
			a.alive=false
			a.collision_layer=0
			a.equipment.collision_layer=0

	# Match the counter to the remaining guards.
	g.germans_alive=150
	for a in g.friendlies:
		if a.boat==null and attack.size()<240:attack.append(a)
	for pair in g.rocket_teams:
		if pair.carrier not in attack:attack.append(pair.carrier)
	for i in range(attack.size()):
		var a=attack[i]
		a.truck=null
		a.boat=null
		a.position=g.world.on_ground(Vector3((i%24-11.5)*12,0,-338+(i/24)*1.3))
		a.home=a.position
		a.lane=a.position.x
		a.sector=g.Layout.sector_for(a.position.x)

		# Skip the beach stages of the assault plan.
		a.assault_stage=6
		a.order="assault"
		a.state="advance"
		a.set_reserve(false)
	g.phase="playing"
	g.elapsed=300

	# Wake the garrison and tanks so the fight starts immediately.
	g.activate_town()
	g.rebuild_spatial()
	var hz=Engine.physics_ticks_per_second
	var duration=int(OS.get_environment("TOWN_ASSAULT_SECONDS")) if OS.has_environment("TOWN_ASSAULT_SECONDS") else 180
	for tick in range(duration*hz):
		await physics_frame
		var delta=1.0/hz
		g.elapsed+=delta
		for tank in g.tanks:tank.tick(delta)
		for pair in g.rocket_teams:pair.tick(delta)
		g.step_heavy_projectiles(delta)
		if tick%maxi(1,hz/2)==0:
			g.rebuild_spatial()
			for a in attack+g.enemies:
				if a.alive and not a.staged:a.think(g.elapsed)
		g.step_projectiles(delta)
		g.update_tracers(delta)
		g.update_flashes()
		for effect in g.effects.duplicate():
			effect.time-=delta
			if effect.time<=0:
				effect.node.queue_free()
				g.effects.erase(effect)
		if tick%(30*hz)==0:
			var rec={"seconds":tick/hz,"allies":attack.filter(func(a):return a.alive).size(),"enemies":g.germans_alive,"tanks":g.tanks.map(func(t):return {"hp":t.health,"p":str(t.position)}),"rockets":g.rocket_teams.map(func(t):return {"shots":t.shots,"left":t.rockets,"carrier":t.carrier.index if t.carrier!=null else -1,"loader":t.loader.index if t.loader!=null else -1,"p":str(t.carrier.position if t.carrier!=null else t.dropped_at)}),"inside":attack.filter(func(a):return a.alive and a.position.z< -370).size()}
			snapshots.append(rec)
			print("TOWN ",JSON.stringify(rec))
	var survivors=attack.filter(func(a):return a.alive)
	var result={"fixture":"244 riflemen/engineers/bazooka carriers at town approach versus 150 town guards and three tanks; original health/ammo, no player intervention","snapshots":snapshots,"survivors":survivors.map(func(a):return {"index":a.index,"p":str(a.position),"goal":str(a.destination),"state":a.state,"cursor":a.path_cursor,"path":str(a.path),"stuck":a.stuck}),"enemies":g.germans_alive,"tanks":g.tanks.map(func(t):return {"hp":t.health,"p":str(t.position)}),"houses_collapsed":g.world.houses.filter(func(h):return h.collapsed).size()}
	FileAccess.open("res://reviews/omaha/town-assault.json",FileAccess.WRITE).store_string(JSON.stringify(result,"  "))
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit()
