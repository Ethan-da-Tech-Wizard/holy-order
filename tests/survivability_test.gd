## Regression test for the player's survivability rules (the 300 hit point
## knight, truck armour, reduced passenger damage) across all three missions.
## Checks (labels print as PASS/FAIL):
##   - all three player scripts start with 300 health and 300 max health;
##   - Ardennes truck armour is drawn with shared batches except the wheels;
##   - a 120-round MG burst into the passenger compartment does not hurt the
##     seated player (steel stops it) while counting at least 100 hits;
##   - a burst of small-arms hits wears but does not destroy a wheel;
##   - blast damage to a seated passenger is reduced to 22% (100 -> 22);
##   - the scripted ambush strike stops the truck and lets the player out alive;
##   - on foot, five 50-damage hits leave 50 health, the sixth ends the game (defeat).
## Results are also written to reviews/survivability-tests.json. Exit code 0 if all pass.
## Run: godot --headless --path <repo> --script res://tests/survivability_test.gd
extends SceneTree

## Collected results {check, ok, data}.
var checks=[]

## SceneTree entry point; defers to run().
func _initialize():call_deferred("run")

## Records and prints one result.
## [param label] description. [param ok] whether it passed. [param data] optional detail.
func check(label:String,ok:bool,data=null):
	checks.append({"check":label,"ok":ok,"data":data})
	print("PASS " if ok else "FAIL ",label," ",data if data!=null else "")

## Runs all checks; see the class comment.
func run():
	set_meta("battle_test",true)

	# Health must agree in every mission because player_stats.gd defines it once.
	for path in ["res://scripts/player.gd","res://scripts/ardennes/player.gd","res://scripts/omaha/player.gd"]:
		var knight=load(path).new()
		check("300 starting and maximum health: "+path,knight.health==300 and knight.max_health==300)
		knight.free()
	var g=load("res://scenes/ardennes.tscn").instantiate()
	root.add_child(g)

	# Removes the frame cap so the test runs as fast as it can.
	Engine.max_fps=0
	await physics_frame
	g.begin()
	g.set_physics_process(false)
	g.player.set_physics_process(false)

	# Freeze AI so only the explicitly scripted shots hit anything.
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

	# Seated passengers take 22% of explosion damage (truck.passenger_damage).
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
