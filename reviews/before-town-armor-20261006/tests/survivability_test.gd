extends SceneTree
var checks=[]
func _initialize():call_deferred("run")
func check(label:String,ok:bool,data=null):
	checks.append({"check":label,"ok":ok,"data":data})
	print("PASS " if ok else "FAIL ",label," ",data if data!=null else "")
func run():
	set_meta("battle_test",true)
	for path in ["res://scripts/player.gd","res://scripts/ardennes/player.gd","res://scripts/omaha/player.gd"]:
		var knight=load(path).new()
		check("300 starting and maximum health: "+path,knight.health==300 and knight.max_health==300)
		knight.free()
	var g=load("res://scenes/ardennes.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.begin()
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for actor in g.actors:actor.set_physics_process(false)
	var truck=g.player.truck
	check("Truck armor uses shared draws without batching rotating wheels",int(truck.get_meta("batched_panels",0))>20 and truck.wheels.all(func(w):return w.render_batch==null))
	var from=truck.to_global(Vector3(3.5,2.6,1.95))
	var hp=g.player.health
	var source=g.enemies[8]
	for i in range(120):g.shoot(source,from,g.player.aim_point(),0.0,50,"mg42")
	check("Steel stops a sustained 120-round burst at the passenger compartment",g.player.health==hp and truck.bullet_hits>=100,{"health":g.player.health,"hits":truck.bullet_hits})
	var wheel=truck.wheel_health[0]
	for i in range(12):truck.wheels[0].damage_at(50,truck.wheels[0].global_position)
	check("Protected wheels survive a belt of small-arms hits",truck.wheel_health[0]>0 and truck.wheel_health[0]<wheel)
	g.hurt_actor(g.player,100,from,"explosion")
	check("Seated passengers receive reduced blast damage",is_equal_approx(hp-g.player.health,22))
	truck.receive_ambush_strike(truck.position)
	check("Ambush strike stops the armored truck and lets the knight out alive",not truck.destroyed and truck.unloaded and g.player.truck==null and g.player.health>0)
	g.player.health=g.player.max_health
	for i in range(5):g.hurt_actor(g.player,50,from,"rifle")
	check("On foot the knight survives five 50-damage hits",g.player.health==50 and g.phase=="playing")
	g.hurt_actor(g.player,50,from,"rifle")
	check("Health remains finite and defeat still works",g.player.health==0 and g.phase=="defeat")
	var file=FileAccess.open("res://reviews/survivability-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":checks.filter(func(c):return c.ok).size(),"total":checks.size(),"checks":checks},"  "))
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit(0 if checks.all(func(c):return c.ok) else 1)
