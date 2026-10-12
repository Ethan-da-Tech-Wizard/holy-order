extends Node3D

const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Interface = preload("res://scripts/interface.gd")
const Sounds = preload("res://scripts/audio.gd")
const Art = preload("res://scripts/art.gd")
var world
var player
var hud
var sounds
var enemies: Array = []
var phase: String = "title"
var elapsed: float = 0
var lint: int = 0
var corpses: Array = []
var rifle_drop: Node3D
var rifle_available: bool = false
var grenade_crate: Node3D
var grenade_available: bool = true
var toast_text: String = ""
var toast_time: float = 0
var hit_flash: float = 0
var damage_flash: float = 0
var last_damage_direction = Vector3.ZERO
var has_seen_rifle: bool = false
var grenades_live: Array = []
var visual_elapsed: float = 0
var subtitle: String = ""
var speaker: String = "THE KNIGHT"
var subtitle_time: float = 0
var pickup_played: bool = false
var cutscene_actor: Node3D
var cutscene_camera: Camera3D
var tea_played: bool = false
var quest: String = "sentry"
var patrol_point = Vector3(42,0,-71)
var patrol_vehicle: Node3D
var patrol_greeter: Node3D
var post_quip_time: float = -1

func _ready():
	Engine.max_fps = 90
	register_inputs()
	world = World.new()
	add_child(world)
	sounds = Sounds.new()
	add_child(sounds)
	player = Player.new()
	player.game = self
	player.position = Vector3(0,0.05,33)
	add_child(player)
	var positions = [Vector3(0,0.03,5),Vector3(-13,0.03,-34),Vector3(-5,0.03,-35),Vector3(6,0.03,-35),Vector3(14,0.03,-43),Vector3(0,0.03,-47)]
	for i in range(positions.size()):
		var enemy = Enemy.new()
		enemy.game = self
		enemy.index = i
		enemy.sentry = i == 0
		enemy.position = positions[i]
		enemy.rotation.y = PI
		add_child(enemy)
		enemies.append(enemy)
	grenade_crate = Art.solid(self,Vector3(0.8,0.5,0.6),Vector3(-20,0.25,-21),Art.material(Color("556044")))
	Art.box(grenade_crate,Vector3(0.3,0.01,0.23),Vector3(0,0.26,0),Art.material(Color("baae82")))
	var label = Label3D.new()
	label.text = "M35"
	label.font_size = 44
	label.pixel_size = 0.005
	label.position = Vector3(0,0.04,0.306)
	grenade_crate.add_child(label)
	var canvas = CanvasLayer.new()
	add_child(canvas)
	hud = Interface.new()
	hud.game = self
	canvas.add_child(hud)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.camera.current = false
	world.world_camera.current = true
	if get_tree().has_meta("restart_playing"):
		get_tree().remove_meta("restart_playing")
		begin()
	var args = OS.get_cmdline_user_args()
	if "--self-test" in args:
		call_deferred("run_tests")
	if "--preview-play" in args:
		begin()
	if "--capture-title" in args:
		call_deferred("capture_title")
	if "--visual-check" in args:
		call_deferred("run_visual_check")

func register_inputs():
	var bindings = {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"sprint":KEY_SHIFT,"jump":KEY_SPACE,"crouch":KEY_C,"prone":KEY_Z,"objectives":KEY_J,"lean_left":KEY_Q,"lean_right":KEY_E,"reload":KEY_R,"interact":KEY_F,"grenade":KEY_G,"weapon_sword":KEY_1,"weapon_rifle":KEY_2,"weapon_fists":KEY_3,"inventory":KEY_TAB,"pause":KEY_ESCAPE,"fullscreen":KEY_F11}
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var key = InputEventKey.new()
		key.physical_keycode = bindings[action]
		InputMap.action_add_event(action,key)
	for action in ["attack","aim"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT if action=="attack" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action,event)

func _unhandled_input(event):
	if event.is_action_pressed("fullscreen"):
		var full = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if event.is_action_pressed("pause"):
		if phase == "playing": pause_game("paused")
		elif phase in ["paused","inventory","objectives","briefing"]: resume_game()
	if event.is_action_pressed("inventory"):
		if phase == "playing": pause_game("inventory")
		elif phase == "inventory": resume_game()
	if event.is_action_pressed("objectives"):
		if phase == "playing": pause_game("objectives")
		elif phase == "objectives": resume_game()
	if phase == "title" and event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		begin()

func _notification(what):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and phase == "playing":
		pause_game("paused")

func _process(delta):
	visual_elapsed += delta
	subtitle_time = maxf(0,subtitle_time-delta)
	if phase != "playing": return
	elapsed += delta
	toast_time = maxf(0,toast_time-delta)
	hit_flash = maxf(0,hit_flash-delta)
	damage_flash = maxf(0,damage_flash-delta)
	if post_quip_time > 0:
		post_quip_time -= delta
		if post_quip_time <= 0 and quest == "outpost":
			say("More Saracens over there. Peculiar helmets.",5)
			toast("ITALIAN OUTPOST MARKED  •  Choose your approach",4)
	if quest == "patrol" and not tea_played:
		var greet = patrol_point+Vector3(-3.0,0,2)
		if player.position.distance_to(greet)<4.3:
			tea_scene()

func _physics_process(delta):
	if phase != "playing": return
	for grenade in grenades_live.duplicate():
		grenade.age += delta
		grenade.fuse -= delta
		grenade.velocity.y -= 14*delta
		var from = grenade.node.position
		var to = from+grenade.velocity*delta
		var q = PhysicsRayQueryParameters3D.create(from,to,1|4)
		var hit = get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			grenade.velocity = grenade.velocity.bounce(hit.normal)*0.35
			to = hit.position+hit.normal*0.1
			if grenade.age > 0.35:
				grenade.fuse = 0
		grenade.node.position = to
		grenade.node.rotate_x(delta*6)
		if grenade.fuse <= 0:
			explode(grenade.node.position)
			grenade.node.queue_free()
			grenades_live.erase(grenade)

func begin():
	phase = "playing" if "--self-test" in OS.get_cmdline_user_args() else "briefing"
	world.menu_knight.visible = false
	player.camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if phase=="playing" else Input.MOUSE_MODE_VISIBLE
	toast("An isolated sentry ahead. The main position lies beyond him.",5)

func pause_game(next_phase: String):
	phase = next_phase
	player.holding_attack = false
	player.power_hold = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func resume_game():
	phase = "playing"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func restart_game():
	get_tree().set_meta("restart_playing",true)
	get_tree().reload_current_scene()

func restart_to_title():
	get_tree().reload_current_scene()

func quit_game():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().quit()

func defeat():
	pause_game("defeat")

func remaining() -> int:
	var count = 0
	for enemy in enemies:
		if enemy.alive: count += 1
	return count

func enemy_down(enemy):
	corpses.append({"enemy":enemy,"looted":false,"lint":1+enemy.index%3,"ammo":18})
	if enemy.sentry:
		rifle_drop = Art.rifle(self)
		rifle_drop.position = enemy.position+Vector3(0.8,0.22,0.55)
		rifle_drop.rotation = Vector3(0,0.5,PI/2)
		enemy.model.gun.visible = false
		rifle_available = true
		quest = "rifle"
		toast("The sentry is down. His rifle lies beside him.",4)
		if not pickup_played and not "--self-test" in OS.get_cmdline_user_args():
			call_deferred("rifle_pickup_scene")
	if remaining() == 0:
		spawn_patrol()

func spawn_patrol():
	if is_instance_valid(patrol_vehicle): return
	quest = "patrol"
	subtitle_time = 0
	post_quip_time = -1
	patrol_vehicle = Art.patrol_truck(self)
	patrol_vehicle.position = patrol_point
	var friendly = Art.soldier(self,true)
	patrol_greeter = friendly.root
	patrol_greeter.position = patrol_point+Vector3(-3.0,0,2)
	patrol_greeter.rotation.y = -0.9
	toast("POSITION CLEARED  •  Meet the British patrol on the road",6)

func objective_text() -> String:
	match quest:
		"sentry": return "Defeat the isolated sentry"
		"rifle": return "Recover the sentry's rifle"
		"outpost": return "Clear the outpost  /  %d remaining" % remaining()
		"patrol": return "Meet the British patrol"
	return "First Contact complete"

func objective_target() -> Vector3:
	match quest:
		"sentry": return enemies[0].position+Vector3(0,2.4,0)
		"rifle": return enemies[0].position+Vector3(0,1.8,0)
		"outpost": return Vector3(1,6,-50)
		"patrol": return patrol_point+Vector3(-3,2.5,2)
	return Vector3.ZERO

func nearest_interaction() -> Dictionary:
	var best: Dictionary = {}
	var distance: float = 3.2
	if rifle_available:
		var d = player.position.distance_to(rifle_drop.position)
		if d < distance:
			best = {"kind":"rifle"}
			distance = d
	# The dropped weapon and the body's lint are separate interactions.
	if not best.is_empty(): return best
	for corpse in corpses:
		var d = player.position.distance_to(corpse.enemy.position)
		if d < distance and not corpse.looted:
			distance = d
			best = {"kind":"body","corpse":corpse}
	if grenade_available and player.position.distance_to(grenade_crate.position) < distance:
		best = {"kind":"grenade"}
	return best

func interaction_prompt() -> String:
	var item = nearest_interaction()
	match item.get("kind",""):
		"rifle": return "F  •  TAKE CARCANO M91  /  6 ROUNDS"
		"body": return "F  •  SEARCH POCKETS"
		"grenade": return "F  •  TAKE ONE BREDA M35 GRENADE"
	return ""

func interact():
	var item = nearest_interaction()
	match item.get("kind",""):
		"rifle":
			rifle_available = false
			rifle_drop.queue_free()
			player.has_rifle = true
			player.ammo = 6
			player.reserve = 0
			player.select_weapon(1)
			quest = "outpost"
			sounds.play("bolt",-8)
			toast("Carcano M91. Six rounds. No spare ammunition.",4)
		"body":
			item.corpse.looted = true
			lint += item.corpse.lint
			player.reserve += item.corpse.ammo
			toast("3 Carcano clips (+18 rounds)  •  Pocket lint +%d" % item.corpse.lint,3.5)
			if lint == 1:
				say("A fine hoard. I shall retire on the proceeds.",4)
		"grenade":
			grenade_available = false
			player.grenades += 1
			toast("Breda M35 grenade acquired. G to throw.",3)

func toast(message: String, duration: float = 3):
	toast_text = message
	toast_time = duration

func say(line: String, duration: float = 5, who: String = "THE KNIGHT"):
	subtitle = line
	subtitle_time = duration
	speaker = who

func rifle_pickup_scene():
	if pickup_played or not rifle_available: return
	pickup_played = true
	phase = "cinematic"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.hands.visible = false
	player.visible = false
	cutscene_actor = Art.knight(self)
	cutscene_actor.position = player.position
	cutscene_actor.rotation.y = player.rotation.y
	if cutscene_actor.has_node("CarriedSword"):
		cutscene_actor.get_node("CarriedSword").visible = false
	# Sheathed sword remains on the belt during the pickup.
	var scabbard = Art.sword(cutscene_actor)
	scabbard.position = Vector3(-0.35,0.97,0.05)
	scabbard.rotation.z = 2.93
	var sheath = Art.box(scabbard,Vector3(0.083,1.0,0.04),Vector3(0,0.66,0),Art.material(Color("4b3b29")))
	sheath.name = "Scabbard"
	cutscene_camera = Camera3D.new()
	add_child(cutscene_camera)
	cutscene_camera.position = player.position+player.global_basis.x*2.3+player.global_basis.z*2.1+Vector3(0,1.6,0)
	cutscene_camera.look_at(player.position+Vector3(0,0.95,0))
	cutscene_camera.fov = 61
	cutscene_camera.current = true
	say("A most discourteous welcome.",2.2)
	var rifle_pos = rifle_drop.global_position
	var reach = Art.gauntlet(cutscene_actor,Vector3(0.4,1.0,-0.28),Vector3(-0.6,0,0))
	var pickup = create_tween()
	pickup.tween_interval(0.75)
	pickup.tween_property(cutscene_actor,"position:y",player.position.y-0.31,0.5)
	pickup.parallel().tween_property(cutscene_actor,"rotation:x",-0.24,0.5)
	pickup.parallel().tween_property(reach,"position",Vector3(0.40,0.62,-0.55),0.5)
	pickup.tween_callback(func():
		rifle_drop.reparent(reach)
		rifle_drop.position = Vector3(0,0.16,0)
		rifle_drop.rotation = Vector3(0.25,0,0.2)
		sounds.play("bolt",-12)
	)
	pickup.tween_property(cutscene_actor,"position:y",player.position.y,0.55)
	pickup.parallel().tween_property(cutscene_actor,"rotation:x",0,0.55)
	pickup.parallel().tween_property(reach,"position",Vector3(0.22,1.20,-0.4),0.55)
	pickup.tween_interval(0.7)
	pickup.tween_callback(finish_pickup_scene)

func finish_pickup_scene():
	rifle_available = false
	player.has_rifle = true
	player.ammo = 6
	player.reserve = 0
	quest = "outpost"
	player.select_weapon(1)
	player.hands.visible = true
	player.visible = true
	player.camera.current = true
	cutscene_camera.queue_free()
	cutscene_actor.queue_free()
	phase = "playing"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	say("Thank goodness everyone innately understands how to chamber and fire a bolt-action rifle.",8)
	toast("CARCANO M91  •  6 ROUNDS  •  F to search the sentry's pockets",4)
	post_quip_time = 8.5

func tea_scene():
	if tea_played: return
	tea_played = true
	phase = "cinematic"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.visible = false
	if is_instance_valid(patrol_greeter): patrol_greeter.visible = false
	var scene_root = Node3D.new()
	add_child(scene_root)
	scene_root.position = patrol_point+Vector3(-4,0,4)
	cutscene_camera = Camera3D.new()
	scene_root.add_child(cutscene_camera)
	cutscene_camera.position = Vector3(0,1.68,3.3)
	cutscene_camera.look_at(scene_root.position+Vector3(0,1.44,0))
	cutscene_camera.fov = 69
	cutscene_camera.current = true
	var host = Art.soldier(scene_root,true)
	host.root.position = Vector3(-0.68,0,0.6)
	host.root.rotation.y = PI-0.12
	host.gun.visible = false
	var passer = Art.soldier(scene_root,true)
	passer.root.position = Vector3(4.4,0,-1.4)
	passer.root.rotation.y = PI/2
	var offered = Art.teacup(host.body)
	offered.position = Vector3(-0.05,1.27,-0.65)
	var held = Art.teacup(cutscene_camera)
	held.position = Vector3(0.20,-0.19,-0.40)
	held.visible = false
	var hand = Art.gauntlet(held,Vector3(0.07,-0.07,0.015),Vector3(0.1,0,-0.2))
	say("Welcome, old crusader. Climb in. Have a cup of tea.",4.0,"BRITISH PATROL LEADER")
	var tw = create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(cutscene_camera,"position",Vector3(3.6,2.28,-3.0),0.7)
	tw.tween_callback(func(): cutscene_camera.look_at(scene_root.position+Vector3(-0.68,1.5,0.6)))
	tw.tween_interval(0.5)
	tw.tween_callback(func(): offered.visible=false; held.visible=true)
	tw.tween_property(held,"position",Vector3(0.08,-0.09,-0.19),0.55)
	tw.parallel().tween_property(held,"rotation:x",0.47,0.55)
	tw.tween_interval(0.55)
	tw.tween_property(held,"position",Vector3(0.20,-0.19,-0.40),0.4)
	tw.parallel().tween_property(held,"rotation:x",0.0,0.4)
	tw.tween_callback(func(): say("Oh, wow. It's just like plain water.",2.6))
	tw.tween_interval(2.65)
	tw.tween_callback(func(): say("Never mind that! It's just the war-ration blend.",3.0,"BRITISH PATROL LEADER"))
	tw.tween_property(passer.root,"position:x",1.55,2.5)
	tw.tween_callback(func(): passer.root.rotation.y=PI-0.4; say("It's the hot-water-and-desert-sand blend.",3.1,"PASSING SOLDIER"))
	tw.tween_interval(3.2)
	tw.tween_callback(func():
		player.visible=true
		player.camera.current=true
		quest="complete"
		scene_root.queue_free()
		sounds.play("victory",-8)
		pause_game("victory")
	)

func alert_near(pos: Vector3, radius: float):
	for enemy in enemies:
		if enemy.alive and enemy.position.distance_to(pos) < radius:
			enemy.alerted = true

func tracer(start: Vector3, end: Vector3, color: Color):
	var mat = Art.material(color).duplicate()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var trace = Art.segment(self,start,end,0.009,mat)
	get_tree().create_timer(0.055).timeout.connect(trace.queue_free)

func impact(pos: Vector3, color: Color):
	var mat = Art.material(color)
	for i in range(5):
		var p = Art.sphere(self,0.035,pos,mat)
		var tw = create_tween().set_parallel(true)
		tw.tween_property(p,"position",pos+Vector3(randf_range(-0.5,0.5),randf_range(0.1,0.6),randf_range(-0.5,0.5)),0.25)
		tw.tween_property(p,"scale",Vector3.ZERO,0.4)
		tw.finished.connect(p.queue_free)

func throw_grenade(pos: Vector3, direction: Vector3):
	var root = Node3D.new()
	add_child(root)
	root.position = pos+direction*0.6
	Art.cylinder(root,0.072,0.13,Vector3.ZERO,Art.material(Color("973e32"),0.4),0.06)
	Art.box(root,Vector3(0.09,0.025,0.025),Vector3(0,0.09,0),Art.material(Color("5d6258"),0.7))
	# M35 impact grenade: a short arming interval, impact detonation, timed fallback.
	grenades_live.append({"node":root,"velocity":direction*14+Vector3(0,3,0),"fuse":4.0,"age":0.0})

func explode(pos: Vector3):
	sounds.at("rifle",pos,7)
	impact(pos,Color("e5b373"))
	var flash = OmniLight3D.new()
	flash.position = pos+Vector3(0,0.5,0)
	flash.light_color = Color("ffb956")
	flash.light_energy = 7
	flash.omni_range = 12
	add_child(flash)
	var tw = create_tween()
	tw.tween_property(flash,"light_energy",0,0.25)
	tw.finished.connect(flash.queue_free)
	for enemy in enemies:
		if enemy.alive and enemy.position.distance_to(pos) < 7:
			var q = PhysicsRayQueryParameters3D.create(pos+Vector3(0,0.2,0),enemy.position+Vector3(0,1,0),1)
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				enemy.take_damage(150)
	if player.position.distance_to(pos) < 6 and phase == "playing":
		var q = PhysicsRayQueryParameters3D.create(pos+Vector3(0,0.2,0),player.position+Vector3(0,1,0),1)
		if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			player.take_damage(60,pos,"blast")

func capture_title():
	await get_tree().create_timer(3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://reviews/start-screen.png")
	print("TITLE_SCREEN_CAPTURED")
	get_tree().quit()

func run_tests():
	await get_tree().physics_frame
	await get_tree().physics_frame
	var tests = load("res://tests/encounter_test.gd").new()
	add_child(tests)
	tests.run(self)

func run_visual_check():
	var check_script=load("res://tests/visual_check.gd").new()
	add_child(check_script)
	check_script.run(self)
