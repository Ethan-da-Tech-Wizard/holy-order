## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script tests/omaha_routes.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Rule checks for the Omaha attackers' routing and several mission rules.
##
## Checks (printed as PASS/FAIL, exit code not set by this script):
##   - assault_goal() walks a soldier through its stages: to the bunker's rear door
##     and inside (stage 4), back out the rear once the gun room is clear (stage 5), then on to sweep remaining defenders (stage 6);
##   - once the sector is clear, column members in the village keep attacking inland;
##   - a flamethrower burns a visible target in range, but concrete blocks the flame;
##   - securing three bunkers and clearing the village does not end the mission before wave two lands.
## Run: godot --headless --path <repo> --script res://tests/omaha_routes.gd
extends SceneTree

## The Omaha battle controller.
var g

## Collected results {check, ok}.
var checks=[]

## SceneTree entry point; defers to run().
func _initialize():call_deferred("run")

## Records and prints one result.
## [param label] description. [param ok] pass/fail.
func check(label:String,ok:bool):
	checks.append({"check":label,"ok":ok})
	print("PASS " if ok else "FAIL ",label)

## Runs the checks in the order above.
func run():
	set_meta("battle_test",true)
	g=load("res://scenes/omaha.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.set_physics_process(false)
	var actor=g.friendlies[0]
	actor.truck=null
	actor.sector=3
	var center=g.world.anchors[3]
	var path=[]

	# Teleport the soldier to each goal in turn so the stage counter advances exactly as it would when walking there.
	for i in range(5):
		var p=g.assault_goal(actor)
		actor.position=p
		g.assault_goal(actor)
		path.append({"stage":actor.assault_stage,"point":str(p)})
	check("Assault reaches the rear door then stays inside bunker",actor.assault_stage==4 and actor.position.distance_to(center)<3)
	for e in g.enemies:
		if e.sector==3 and e.role=="bunker_mg":e.alive=false
	g.assault_goal(actor)
	check("Cleared gun room leads back through rear exit",actor.assault_stage==5 and g.assault_goal(actor).z<center.z-5)
	actor.position=g.assault_goal(actor)
	g.assault_goal(actor)
	check("Squad sweeps remaining strongpoint defenders",actor.assault_stage==6 and g.assault_goal(actor).distance_to(center)>3)

	# Everyone is parked so only the flamethrower fixture can act; positions are chosen 14 m apart on the beach so the target is within the 23 m jet.
	# Exercise real flame damage and physical shielding independently of random combat.
	for a in g.actors:
		a.staged=true
		a.collision_layer=0
		a.equipment.collision_layer=0
	var source=g.friendlies.filter(func(a):return a.weapon_kind=="flamethrower")[0]
	var target=g.enemies[50]
	source.staged=false
	source.truck=null
	source.position=g.world.on_ground(Vector3(500,0,-80))
	target.staged=false
	target.alive=true
	target.health=100
	target.position=g.world.on_ground(Vector3(500,0,-94))
	target.collision_layer=4
	await physics_frame
	await physics_frame
	g.flame_jet(source,source.eye(),target.aim_point())
	check("Flamethrower burns a visible target within range",target.health<100)
	var before=target.health
	var wall=g.world.strong(Vector3(6,5,1),g.world.on_ground(Vector3(500,0,-88))+Vector3(0,2.5,0),g.world.concrete)
	await physics_frame
	await physics_frame
	g.flame_jet(source,source.eye(),target.aim_point())
	check("Concrete stops flame damage through walls",target.health==before)

	# Victory must come from objectives: here every German and tank is dead and three sectors captured, but the second wave has not landed, so the game must keep playing.
	# No arbitrary casualty quota: actual objectives determine victory.
	g.phase="playing"
	g.player.health=100
	g.player.truck=null
	g.player.position=g.world.on_ground(Vector3(0,0,g.Layout.CHURCH+20))
	for e in g.enemies:e.alive=false
	g.capture.assign([10.0,10.0,10.0,0.0,0.0,0.0,0.0,0.0])
	g.second_wave_landed=false
	g.update_objectives(12)
	check("Securing village does not skip reinforcement objective",g.phase=="playing")
	g.second_wave_landed=true
	g.update_objectives(1)
	check("Three exits plus village plus wave two wins",g.phase=="victory")
	var f=FileAccess.open("res://reviews/omaha/routes-and-objectives.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"route":path},"  "))
	g.queue_free()
	await process_frame
	await process_frame
	quit(0 if checks.all(func(c):return c.ok) else 1)
