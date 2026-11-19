# ==============================================================================
# Program: survivability_test.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Automated test script verifying runtime performance, physics stability, or behavior correctness for survivability_test.gd.
# ==============================================================================
## Survivability test for the knight and the armoured truck in the Ardennes mission.
##
## Checks that all three player scripts start with 300 health, that the truck's steel stops a
## sustained MG42 burst and spares its wheels, that seated passengers take reduced blast damage
## (100 becomes 22), that the scripted ambush strike lets the knight out alive, and that health
## stays finite on foot (five 50-point hits survive, the sixth is defeat). Writes
## reviews/survivability-tests.json; exit code 1 on any failure.
## Run: `godot --headless --path . --script res://tests/survivability_test.gd`.
extends SceneTree

# {check, ok, data} records; `data` carries the measured numbers for the report.
var checks=[]
func _initialize():call_deferred("run")

## Record and print one result.
func check(label:String,ok:bool,data=null):
	checks.append({"check":label,"ok":ok,"data":data})
	print("PASS " if ok else "FAIL ",label," ",data if data!=null else "")

## Run all checks in order; later checks use the state left by earlier ones.
func run():
	# Test-mode flag for the battle scripts.
	set_meta("battle_test",true)
	# The same starting health applies to all three theaters' player scripts (desert, Ardennes, Omaha).
	for path in ["res://scripts/player.gd","res://scripts/ardennes/player.gd","res://scripts/omaha/player.gd"]:
		var knight=load(path).new()
		check("300 starting and maximum health: "+path,knight.health==300 and knight.max_health==300)
		knight.free()
	# Instantiate the Ardennes mission and freeze it so only the scripted actions happen.
	var g=load("res://scenes/ardennes.tscn").instantiate()
	root.add_child(g)
	Engine.max_fps=0
	await physics_frame
	g.begin()
	g.set_physics_process(false)
	g.player.set_physics_process(false)
	for actor in g.actors:actor.set_physics_process(false)
	# The player starts seated in the truck.
	var truck=g.player.truck
	# Wheels must stay un-batched because they rotate, while the armour panels (more than 20) must share draws.
	check("Truck armor uses shared draws without batching rotating wheels",int(truck.get_meta("batched_panels",0))>20 and truck.wheels.all(func(w):return w.render_batch==null))
	# Fire point on the truck's right side at passenger height.
	var from=truck.to_global(Vector3(3.5,2.6,1.95))
	var hp=g.player.health
	# An enemy soldier is the shooter; 120 rounds of MG42 at the player.
	var source=g.enemies[8]
	for i in range(120):g.shoot(source,from,g.player.aim_point(),0.0,50,"mg42")
	# Steel should stop everything: health unchanged and at least 100 hits recorded on the truck.
	check("Steel stops a sustained 120-round burst at the passenger compartment",g.player.health==hp and truck.bullet_hits>=100,{"health":g.player.health,"hits":truck.bullet_hits})
	# Wheels: 12 hits of 50 damage must hurt but not destroy a wheel.
	var wheel=truck.wheel_health[0]
	for i in range(12):truck.wheels[0].damage_at(50,truck.wheels[0].global_position)
	check("Protected wheels survive a belt of small-arms hits",truck.wheel_health[0]>0 and truck.wheel_health[0]<wheel)
	# An explosion hits for 100 but seated passengers only take 22.
	g.hurt_actor(g.player,100,from,"explosion")
	check("Seated passengers receive reduced blast damage",is_equal_approx(hp-g.player.health,22))
	# The ambush strike halts the truck, unloads the troops and leaves the player alive and out of the truck.
	truck.receive_ambush_strike(truck.position)
	check("Ambush strike stops the armored truck and lets the knight out alive",not truck.destroyed and truck.unloaded and g.player.truck==null and g.player.health>0)
	# On foot: five 50-point rifle hits leave 50 health; the sixth is lethal, giving the defeat phase.
	g.player.health=g.player.max_health
	for i in range(5):g.hurt_actor(g.player,50,from,"rifle")
	check("On foot the knight survives five 50-damage hits",g.player.health==50 and g.phase=="playing")
	g.hurt_actor(g.player,50,from,"rifle")
	check("Health remains finite and defeat still works",g.player.health==0 and g.phase=="defeat")
	# Write the report and shut down.
	var file=FileAccess.open("res://reviews/survivability-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":checks.filter(func(c):return c.ok).size(),"total":checks.size(),"checks":checks},"  "))
	g.phase="title"
	g.queue_free()
	await process_frame
	await process_frame
	quit(0 if checks.all(func(c):return c.ok) else 1)
