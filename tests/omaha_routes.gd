extends SceneTree
var g
var checks=[]
func _initialize():call_deferred("run")
func check(label:String,ok:bool):
	checks.append({"check":label,"ok":ok})
	print("PASS " if ok else "FAIL ",label)
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
	for e in g.enemies:
		if e.sector==3 and e.role!="town_guard":e.alive=false
	actor.position=g.world.on_ground(Vector3(-24,0,-363))
	actor.assault_stage=6
	var inland_goal=g.assault_goal(actor)
	check("Town columns keep attacking inland despite survivors in another beach sector",inland_goal.z<g.Layout.TOWN_FRONT)
	# Exercise real flame damage and physical shielding independently of random combat.
	for a in g.actors:
		a.staged=true
		a.collision_layer=0
		a.equipment.collision_layer=0
	var source=g.friendlies.filter(func(a):return a.weapon_kind=="flamethrower")[0]
	var target=g.enemies[50]
	source.staged=false
	source.truck=null
	source.position=g.world.on_ground(Vector3(250,0,-80))
	target.staged=false
	target.alive=true
	target.health=100
	target.position=g.world.on_ground(Vector3(250,0,-94))
	target.collision_layer=4
	await physics_frame
	await physics_frame
	g.flame_jet(source,source.eye(),target.aim_point())
	check("Flamethrower burns a visible target within range",target.health<100)
	var before=target.health
	var wall=g.world.strong(Vector3(6,5,1),g.world.on_ground(Vector3(250,0,-88))+Vector3(0,2.5,0),g.world.concrete)
	await physics_frame
	await physics_frame
	g.flame_jet(source,source.eye(),target.aim_point())
	check("Concrete stops flame damage through walls",target.health==before)
	# No arbitrary casualty quota: actual objectives determine victory.
	g.phase="playing"
	g.player.health=100
	g.player.truck=null
	g.player.position=g.world.on_ground(Vector3(0,0,g.Layout.CHURCH+20))
	for e in g.enemies:e.alive=false
	for tank in g.tanks:tank.alive=false
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
