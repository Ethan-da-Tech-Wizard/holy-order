extends Node

var checks: Array = []
var failures: Array[String] = []

func check(condition: bool, description: String):
	checks.append({"check":description,"passed":condition})
	print(("PASS " if condition else "FAIL ")+description)
	if not condition: failures.append(description)

func ticks(count: int):
	for i in range(maxi(1,roundi(count*Engine.physics_ticks_per_second/60.0))): await get_tree().physics_frame

func run(g):
	check(g.phase=="title","Launch stops at the start screen")
	check(g.enemies.size()==6 and g.remaining()==6,"Six defenders; sentry separated from the line")
	check(g.enemies[0].position.distance_to(g.enemies[1].position)>35,"First sentry is over 35 metres from the group")
	check(g.player.weapon==0 and not g.player.has_rifle and g.player.ammo==0,"Player starts with sword, armour and no firearm")
	check(InputMap.action_get_events("lean_left")[0].physical_keycode==KEY_Q and InputMap.action_get_events("lean_right")[0].physical_keycode==KEY_E,"Q/E are lean; F remains available for loot")
	await ticks(5)
	check(g.player.health==g.player.max_health and g.enemies[0].shots_fired==0,"World is safe and idle at the title screen")
	g.begin()
	for e in g.enemies:
		e.cooldown=999
		e.set_physics_process(false)
	await ticks(3)
	var before = g.player.position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await ticks(24)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	check(g.player.position.z<before.z-1.0 and g.player.stamina<100,"W plus Shift moves the player and consumes stamina")
	g.player.velocity=Vector3.ZERO
	g.player.position=Vector3(18,0.04,25)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	Input.action_press("aim")
	await ticks(30)
	check(g.player.is_charging and g.player.velocity.length()>9,"Shift plus right mouse produces a fast melee charge")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_release("aim")
	g.player.velocity=Vector3.ZERO
	g.player.prone=true
	await ticks(18)
	check(g.player.eye_height<0.65 and g.player.shape.shape.height<0.75,"Prone crawling lowers both viewpoint and collision")
	g.player.prone=false
	g.player.position=Vector3(0,0.04,20)
	await ticks(3)
	Input.action_press("lean_left")
	await ticks(15)
	check(g.player.camera.position.x< -0.1,"Leaning offsets the viewpoint")
	Input.action_release("lean_left")
	Input.action_press("crouch")
	await ticks(18)
	check(g.player.eye_height<1.3 and g.player.shape.shape.height<1.4,"Crouching lowers eyes and collision height")
	Input.action_release("crouch")
	await ticks(18)
	g.player.position=Vector3(5,0.01,30.0)
	g.player.rotation=Vector3.ZERO
	g.player.head.rotation=Vector3.ZERO
	await ticks(3)
	check(g.player.try_mantle(),"Space can mantle the low sandbag wall")
	await ticks(34)
	check(g.player.position.y>0.95,"Mantle lands above the cover rather than inside it")
	# A real physics wall must occlude the enemy raycast.
	g.player.position=Vector3(0,0.03,30)
	await ticks(2)
	var wall = g.Art.solid(g,Vector3(3,3,0.5),Vector3(0,1.5,28),g.Art.material(Color.GRAY))
	await ticks(2)
	check(not g.enemies[0].can_see_player(),"Enemy line of sight respects solid cover")
	wall.queue_free()
	await ticks(3)
	check(g.enemies[0].can_see_player(),"Sentry sees the player when the obstruction is removed")
	g.player.position=g.enemies[0].position+Vector3(1.45,0,0.6)
	g.player.velocity=Vector3.ZERO
	await ticks(3)
	g.player.camera.look_at(g.enemies[0].position+Vector3(0,1.3,0))
	g.player.melee_hit()
	check(not g.enemies[0].alive and g.remaining()==5,"Sword collision defeats the isolated sentry")
	check(g.rifle_available,"The sentry drops the recoverable rifle")
	# Exercise the real cinematic rather than granting its outcome directly.
	g.rifle_pickup_scene()
	check(g.phase=="cinematic","Pickup animation suspends combat")
	await get_tree().create_timer(3.5).timeout
	check(g.phase=="playing" and g.player.has_rifle and g.player.ammo==6 and g.player.reserve==0,"Pickup returns to first person with exactly six rounds and no reserve")
	check(g.subtitle.contains("innately understands"),"Requested rifle quip appears as a subtitle")
	g.interact()
	var lint_before = g.lint
	g.interact()
	check(lint_before>0 and g.lint==lint_before,"Body loot yields lint once; repeat interaction cannot duplicate it")
	check(g.player.ammo==6 and g.player.reserve==18,"Looting supplies three six-round clips exactly once")
	g.player.reload_weapon()
	check(g.player.ammo==6 and g.player.reserve==18,"Reloading a full rifle does not waste reserve ammunition")
	g.player.select_weapon(0)
	check(g.player.slung.visible and not g.player.sheathed.visible,"Rifle is slung while the sword is drawn")
	g.player.select_weapon(2)
	check(g.player.slung.visible and g.player.sheathed.visible and g.player.fists.visible,"Fists mode stows both rifle and sword")
	g.player.select_weapon(1)
	g.player.position=g.enemies[2].position+Vector3(0,0,-3)
	g.player.velocity=Vector3.ZERO
	await ticks(3)
	g.player.camera.look_at(g.enemies[2].position+Vector3(0,1.35,0))
	g.player.cooldown=0
	g.player.attack()
	check(not g.enemies[2].alive and g.player.hit_count==1,"Rifle raycast hits and defeats a defender")
	g.player.camera.rotation=Vector3.ZERO
	g.player.head.rotation=Vector3(-1.1,0,0)
	for i in range(5):
		g.player.cooldown=0
		g.player.attack()
	check(g.player.ammo==0 and g.player.shot_count==6,"Only six rifle shots are available")
	g.player.cooldown=0
	g.player.attack()
	check(g.player.ammo==0 and g.player.shot_count==6,"An empty rifle cannot fire a seventh shot")
	g.player.reload_weapon()
	await ticks(145)
	check(g.player.ammo==6 and g.player.reserve==12,"R reloads from reserves with ammunition conserved")
	g.player.select_weapon(2)
	g.player.position=g.enemies[1].position+Vector3(0,0,1.4)
	g.player.head.rotation=Vector3.ZERO
	g.player.camera.rotation=Vector3.ZERO
	await ticks(3)
	g.player.camera.look_at(g.enemies[1].position+Vector3(0,1.25,0))
	for i in range(3): g.player.melee_hit()
	check(not g.enemies[1].alive,"Steel gauntlets can defeat a defender")
	g.interact()
	check(g.lint>lint_before,"Lint stacks across multiple bodies")
	g.player.position=g.grenade_crate.position+Vector3(1,0,0)
	g.interact()
	check(g.player.grenades==3 and g.player.reserve==36,"Supply crate adds three grenades without adding rifle ammunition")
	var blast_target = g.enemies[3]
	g.player.position=Vector3(25,0,-20)
	g.throw_grenade(blast_target.position+Vector3(0,1.0,-1),Vector3.DOWN)
	await ticks(50)
	check(not blast_target.alive and g.grenades_live.is_empty(),"Thrown impact grenade detonates and damages a nearby defender")
	g.player.select_weapon(2)
	g.player.position=g.enemies[4].position+Vector3(0,0,-1.4)
	g.player.velocity=Vector3.ZERO
	g.player.head.rotation=Vector3.ZERO
	await ticks(3)
	g.player.camera.look_at(g.enemies[4].position+Vector3(0,1.25,0))
	g.player.cooldown=0
	g.player.attack(1.2)
	await ticks(12)
	check(not g.enemies[4].alive,"A held gauntlet power attack deals a heavier blow")
	g.pause_game("inventory")
	var health_before=g.player.health
	g.player.take_damage(100,g.enemies[2].position)
	check(g.player.health==health_before,"Inventory pauses incoming damage")
	g.resume_game()
	g.player.health=10
	g.player.take_damage(20,g.enemies[2].position)
	check(g.phase=="defeat","Zero health reaches the defeat/retry screen")
	g.player.health=100
	g.resume_game()
	for enemy in g.enemies:
		if enemy.alive: enemy.take_damage(200)
	check(g.phase=="playing" and g.remaining()==0 and g.quest=="patrol","Last kill opens the road rendezvous, not an immediate ending")
	check(is_instance_valid(g.patrol_vehicle) and g.patrol_vehicle.position==g.patrol_point,"Patrol vehicle spawns on its fixed road location")
	check(not g.tea_played,"Player must approach the patrol before the greeting")
	g.player.position=g.patrol_point+Vector3(-3,0,5)
	await ticks(3)
	check(g.phase=="cinematic" and g.speaker=="BRITISH PATROL LEADER","British patrol begins the tea epilogue")
	await get_tree().create_timer(11.1).timeout
	check(g.subtitle.contains("desert-sand blend"),"Passing soldier delivers the requested tea punchline")
	await get_tree().create_timer(3.4).timeout
	check(g.phase=="victory","Tea scene ends at the test-complete screen")
	var report={"passed":failures.is_empty(),"checks":checks,"failures":failures,"scope":"Automated headless encounter and input checks, including both cinematics. Human playtesting remains pending."}
	var file=FileAccess.open("res://reviews/encounter-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("ENCOUNTER_TESTS_COMPLETE ",checks.size()," checks; ",failures.size()," failures")
	g.sounds.music.stop()
	await ticks(4)
	get_tree().quit(0 if failures.is_empty() else 1)
