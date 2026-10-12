extends Node3D

const World = preload("res://scripts/world.gd")
const Player = preload("res://scripts/player.gd")
const Enemy = preload("res://scripts/enemy.gd")
const Interface = preload("res://scripts/interface.gd")
const Sounds = preload("res://scripts/audio.gd")
const Art = preload("res://scripts/art.gd")
var world
var mg_nest
var demolition
var friendlies: Array=[]
var player_mounted: bool=false
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
	Engine.max_fps = 60
	register_inputs()
	world = World.new()
	world.game = self
	add_child(world)
	sounds = Sounds.new()
	add_child(sounds)
	player = Player.new()
	player.game = self
	player.position = Vector3(0,0.05,53)
	add_child(player)
	var positions = world.village.enemy_positions
	for i in range(positions.size()):
		var enemy = Enemy.new()
		enemy.game = self
		enemy.index = i
		enemy.sentry = i == 0
		enemy.role = world.village.enemy_roles[i]
		enemy.position = positions[i]
		enemy.rotation.y = PI
		add_child(enemy)
		enemies.append(enemy)
	grenade_crate = Art.solid(self,Vector3(0.8,0.5,0.6),Vector3(20.5,0.25,-9),Art.material(Color("556044")))
	Art.box(grenade_crate,Vector3(0.3,0.01,0.23),Vector3(0,0.26,0),Art.material(Color("baae82")))
	var label = Label3D.new()
	label.text = "M35"
	label.font_size = 44
	label.pixel_size = 0.005
	label.position = Vector3(0,0.04,0.306)
	grenade_crate.add_child(label)
	mg_nest=load("res://scripts/mg_nest.gd").new()
	mg_nest.game=self
	mg_nest.position=Vector3(3,0,-49)
	add_child(mg_nest)
	demolition=load("res://scripts/demolition.gd").new()
	demolition.game=self
	add_child(demolition)
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

	preload("res://scripts/graphics.gd").install(self)

func register_inputs():
	var bindings = {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"sprint":KEY_SHIFT,"jump":KEY_SPACE,"crouch":KEY_C,"prone":KEY_Z,"objectives":KEY_J,"lean_left":KEY_Q,"lean_right":KEY_E,"reload":KEY_R,"interact":KEY_F,"grenade":KEY_G,"weapon_sword":KEY_1,"weapon_rifle":KEY_2,"weapon_fists":KEY_3,"weapon_shovel":KEY_4,"weapon_demolition":KEY_5,"detonate":KEY_B,"inventory":KEY_TAB,"pause":KEY_ESCAPE,"fullscreen":KEY_F11}
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
	corpses.append({"enemy":enemy,"looted":false,"weapon_taken":enemy.sentry,"lint":1+enemy.index%3})
	if enemy.sentry and enemy.weapon_health>0:
		rifle_drop = Art.rifle(self)
		rifle_drop.position = enemy.position+Vector3(0.8,0.22,0.55)
		rifle_drop.rotation = Vector3(0,0.5,PI/2)
		enemy.model.gun.visible = false
		enemy.weapon_hitbox.set_active(false)
		rifle_available = true
		quest = "rifle"
		toast("The sentry is down. His rifle lies beside him.",4)
		if not pickup_played and player.position.distance_to(enemy.position)<4.5 and not "--self-test" in OS.get_cmdline_user_args():
			call_deferred("rifle_pickup_scene")
	elif enemy.sentry:
		quest="outpost"
		toast("The sentry's rifle is ruined. Recover another weapon in the village.",5)
	if remaining() == 0:
		spawn_patrol()

func spawn_patrol():
	if is_instance_valid(patrol_vehicle): return
	quest = "patrol"
	subtitle_time = 0
	post_quip_time = -1
	patrol_vehicle = Art.patrol_truck(self)
	patrol_vehicle.position = patrol_point
	world.make_loose_props_breakable(patrol_vehicle)
	var friendly=Enemy.new()
	friendly.game=self
	friendly.team=1
	friendly.index=6
	friendly.role="hold"
	friendly.position=patrol_point+Vector3(-3.0,0,2)
	add_child(friendly)
	friendlies.append(friendly)
	patrol_greeter=friendly
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
		"outpost": return Vector3(0,6,-35)
		"patrol": return patrol_point+Vector3(-3,2.5,2)
	return Vector3.ZERO

func interaction_visible(point: Vector3, allowed=null) -> bool:
	var ray=PhysicsRayQueryParameters3D.create(player.camera.global_position,point,1)
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or hit.collider==allowed

func nearest_interaction() -> Dictionary:
	if player_mounted:return {"kind":"leave_mg"}
	var best: Dictionary={}
	var distance: float=3.2
	if is_instance_valid(demolition):
		if is_instance_valid(demolition.active) and player.position.distance_to(demolition.active.global_position)<2.8 and interaction_visible(demolition.active.global_position):
			return {"kind":"recover_satchel"}
		if demolition.available() and player.position.distance_to(demolition.cache.global_position)<3.0 and interaction_visible(demolition.cache.global_position,demolition.cache):
			return {"kind":"demolition"}
	if mg_nest and not is_instance_valid(mg_nest.operator) and mg_nest.usable() and player.position.distance_to(mg_nest.operator_position())<2.5 and interaction_visible(mg_nest.operator_position()+Vector3(0,0.9,0)):
		return {"kind":"mg"}
	if rifle_available and is_instance_valid(rifle_drop):
		var d=player.position.distance_to(rifle_drop.global_position)
		if d<distance and interaction_visible(rifle_drop.global_position+Vector3(0,0.25,0)):
			return {"kind":"rifle"}
	for corpse in corpses:
		var d=player.position.distance_to(corpse.enemy.position)
		if d<distance and interaction_visible(corpse.enemy.position+Vector3(0,0.42,0)):
			if not corpse.looted:
				distance=d
				best={"kind":"body","corpse":corpse}
			elif not player.has_rifle and not corpse.weapon_taken and corpse.enemy.weapon_health>0:
				distance=d
				best={"kind":"spare_rifle","corpse":corpse}
	if grenade_available and player.position.distance_to(grenade_crate.position)<distance and interaction_visible(grenade_crate.position,grenade_crate):
		best={"kind":"grenade"}
		distance=player.position.distance_to(grenade_crate.position)
	var door=world.nearby_door(player.camera.global_position,2.7)
	if door and interaction_visible(door.interaction_position(),door.leaf):
		var toward=(door.interaction_position()-player.camera.global_position).normalized()
		if (-player.camera.global_basis.z).dot(toward)>0.15:
			best={"kind":"door","door":door}
	return best

func interaction_prompt() -> String:
	var item=nearest_interaction()
	match item.get("kind",""):
		"mg":return "F  •  USE BREDA M37  /  %d LOADED + %d TRAYS"%[mg_nest.rounds,mg_nest.spare_trays]
		"leave_mg":return "F  •  DISMOUNT BREDA M37"
		"demolition":return "F  •  TAKE ONE DEMOLITION SATCHEL  /  %d LEFT"%demolition.stock
		"recover_satchel":return "F  •  RECOVER SATCHEL"
		"rifle":return "F  •  TAKE CARCANO M91  /  %d ROUNDS"%enemies[0].rounds
		"body":return "F  •  SEARCH POCKETS / EQUIPMENT"
		"spare_rifle":return "F  •  RECOVER INTACT CARCANO"
		"grenade":return "F  •  TAKE THREE BREDA M35 GRENADES"
		"door":return "F  •  CLOSE DOOR" if item.door.opened else "F  •  OPEN DOOR"
	return ""

func recover_rifle(corpse: Dictionary):
	if corpse.weapon_taken or corpse.enemy.weapon_health<=0:return
	corpse.weapon_taken=true
	corpse.enemy.model.gun.hide()
	corpse.enemy.weapon_hitbox.set_active(false)
	player.has_rifle=true
	player.rifle_health=corpse.enemy.weapon_health
	player.ammo=corpse.enemy.rounds
	corpse.enemy.rounds=0
	player.select_weapon(1)
	toast("Recovered Carcano  •  %d loaded rounds"%player.ammo,3)

func interact():
	var item=nearest_interaction()
	match item.get("kind",""):
		"mg":enter_mg()
		"leave_mg":leave_mg()
		"demolition":demolition.take()
		"recover_satchel":demolition.recover()
		"rifle":
			if not pickup_played and not "--self-test" in OS.get_cmdline_user_args():
				rifle_pickup_scene()
				return
			rifle_available=false
			rifle_drop.queue_free()
			player.has_rifle=true
			player.rifle_health=enemies[0].weapon_health
			player.ammo=enemies[0].rounds
			enemies[0].rounds=0
			player.select_weapon(1)
			quest="patrol" if remaining()==0 else "outpost"
			sounds.play("bolt",-8)
			toast("Carcano M91. %d loaded rounds. F to search pockets."%player.ammo,4)
		"body":
			item.corpse.looted=true
			lint+=item.corpse.lint
			var looted_rounds=item.corpse.enemy.reserve_rounds
			item.corpse.enemy.reserve_rounds=0
			if not player.has_rifle:
				recover_rifle(item.corpse)
			elif not item.corpse.weapon_taken:
				# If already armed, strip the dead soldier's loaded cartridges too.
				looted_rounds+=item.corpse.enemy.rounds
				item.corpse.enemy.rounds=0
			player.reserve+=looted_rounds
			var took_tool=not player.has_shovel
			player.has_shovel=true
			if took_tool:player.shovel_health=110
			toast("Ammunition +%d  •  Pocket lint +%d%s"%[looted_rounds,item.corpse.lint,"  •  Entrenching tool [4]" if took_tool else ""],4)
			if took_tool:say("A shovel. At last, a weapon whose workings I comprehend.",5)
			elif lint==1:say("A fine hoard. I shall retire on the proceeds.",4)
		"spare_rifle":recover_rifle(item.corpse)
		"grenade":
			grenade_available=false
			player.grenades+=3
			toast("Three Breda M35 grenades. G to throw. Masonry can be breached.",4)
		"door":item.door.use()

func damage_environment(hit: Dictionary, amount: float, radius: float):
	if hit.is_empty():return
	if hit.collider.has_method("damage_at"):
		hit.collider.damage_at(amount,hit.position,radius)

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
	player.rifle_health = enemies[0].weapon_health
	player.ammo = enemies[0].rounds
	enemies[0].rounds = 0
	quest = "patrol" if remaining()==0 else "outpost"
	player.select_weapon(1)
	player.hands.visible = true
	player.visible = true
	player.camera.current = true
	cutscene_camera.queue_free()
	cutscene_actor.queue_free()
	phase = "playing"
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	say("Thank goodness everyone innately understands how to chamber and fire a bolt-action rifle.",8)
	toast("CARCANO M91  •  %d ROUNDS  •  F to search the sentry's pockets"%player.ammo,4)
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

func squad(team: int) -> Array:
	return enemies if team==0 else friendlies

func hostile_targets(team: int) -> Array:
	return [player]+friendlies if team==0 else enemies

func emit_noise(pos: Vector3, radius: float, source_team: int=1, kind: String="gunshot"):
	for actor in enemies+friendlies:
		if not actor.alive:continue
		if kind=="footstep" and actor.team==source_team:continue
		var distance=actor.global_position.distance_to(pos)
		var effective=radius
		if kind in ["footstep","melee"]:
			var ray=PhysicsRayQueryParameters3D.create(pos+Vector3(0,0.6,0),actor.eye_position(),1)
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():effective*=0.40
		if distance<effective:
			if actor.team==source_team and actor.alerted and actor.memory>0:continue
			actor.hear_noise(pos,kind)

func alert_near(pos: Vector3, radius: float):
	emit_noise(pos,radius)

func player_can_see(actor) -> bool:
	var target=actor.eye_position()
	if player.camera.is_position_behind(target):return false
	var ray=PhysicsRayQueryParameters3D.create(player.camera.global_position,target,1|4)
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	return not hit.is_empty() and hit.collider==actor

func share_contact(source, point: Vector3):
	for actor in squad(source.team):
		if actor!=source and actor.alive and actor.position.distance_to(source.position)<38:
			actor.hear_contact(point)

func assault_can_move(actor) -> bool:
	var assault: Array=[]
	for ally in squad(actor.team):
		if ally.alive and ally.role=="assault":assault.append(ally)
	if assault.size()<2:return true
	# Alternate bounds. A suppressed / reloading partner cannot give covering fire,
	# so both take cover rather than charging into the same exposed lane.
	var partner=assault[1] if assault[0]==actor else assault[0]
	if partner.suppressed>1 or partner.reload_time>0:return false
	var slot=int(elapsed/5.5)%assault.size()
	return assault[slot]==actor

func notify_projectile(start: Vector3, end: Vector3, source_team: int):
	var segment=end-start
	var length_sq=segment.length_squared()
	if length_sq<0.001:return
	for actor in squad(1-source_team):
		if not actor.alive:continue
		var point=actor.eye_position()
		var t=clampf((point-start).dot(segment)/length_sq,0,1)
		if point.distance_to(start+segment*t)<1.65 and point.distance_to(start)>2:
			actor.near_miss(start)

func fire_projectile(origin: Vector3, aim: Vector3, source, damage: float, environment_damage: float, extra_exclude: Array=[]):
	var team=1 if source==player else source.team
	var end=origin+(aim-origin).normalized()*180
	var query=PhysicsRayQueryParameters3D.create(origin,end,1|2|4|8|16)
	query.collide_with_areas=true
	var exclusions: Array[RID]=[source.get_rid()]
	if source==player:exclusions=player.shot_exclusions()
	elif source.weapon_hitbox:exclusions.append(source.weapon_hitbox.get_rid())
	for rid in extra_exclude:exclusions.append(rid)
	query.exclude=exclusions
	var hit=get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		end=hit.position
		var target=hit.collider
		if target.has_method("receive_hit"):
			target.receive_hit(65 if source!=player else 115,hit.position)
		elif target==player:
			if team==0:player.take_damage(damage,origin,"rifle")
		elif target.has_method("take_damage"):
			if target.team!=team:target.take_damage(damage,false)
		else:damage_environment(hit,environment_damage,0.25)
	notify_projectile(origin,end,team)
	tracer(origin,end,Color("ecc583"))

func enter_mg():
	if not mg_nest.claim(player):return
	player_mounted=true
	player.global_position=mg_nest.operator_position()
	player.velocity=Vector3.ZERO
	player.rotation.y=PI
	player.head.rotation=Vector3.ZERO
	player.camera.rotation=Vector3.ZERO
	player.head.position.y=1.30
	player.hands.hide()
	for box in player.equipment_boxes:box.set_active(false)
	toast("BREDA M37  •  LMB fire / RMB aim / F dismount",4)

func leave_mg():
	if not player_mounted:return
	mg_nest.release(player)
	player_mounted=false
	player.hands.show()
	player.select_weapon(player.weapon)
	player.camera.fov=player.HIP_FOV

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

func explode(pos: Vector3, power: float=340, radius: float=4.4):
	emit_noise(pos,210,1,"blast")
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
	world.blast(pos,power,radius)
	for equipment in get_tree().get_nodes_in_group("equipment_hitbox"):
		if equipment.collision_layer!=0 and equipment.global_position.distance_to(pos)<3.2:
			equipment.receive_hit(115,pos)

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
