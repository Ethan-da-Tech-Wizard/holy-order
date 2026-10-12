extends CharacterBody3D

const Art = preload("res://scripts/art.gd")
const EquipmentHitbox=preload("res://scripts/equipment_hitbox.gd")
var game
var camera: Camera3D
var head: Node3D
var hands: Node3D
var rifle: Node3D
var blade: Node3D
var fists: Node3D
var shovel: Node3D
var has_shovel: bool=false
var rifle_health: float=100
var sword_health: float=140
var shovel_health: float=110
var equipment_boxes: Array=[]
var body_model: Node3D
var slung: Node3D
var scabbard: Node3D
var sheathed: Node3D
var shape: CollisionShape3D
var health: float = 100
var stamina: float = 100
var ammo: int = 0
var reserve: int = 0
var has_rifle: bool = false
var weapon: int = 0 # 0 sword, 1 rifle, 2 fists
var grenades: int = 0
var eye_height: float = 1.68
var is_sprinting: bool = false
var crouched: bool = false
var prone: bool = false
var is_charging: bool = false
var power_hold: float = 0
var holding_attack: bool = false
var strike_power: float = 1
var reload_time: float = 0
var aiming: bool = false
var cooldown: float = 0
var attack_time: float = 0
var attack_pending: bool = false
var bob: float = 0
var step_clock: float = 0
var lean: float = 0
var recoil: float = 0
var sensitivity: float = 0.0021
var shot_count: int = 0
var hit_count: int = 0
var climbing: float = 0
var climb_from: Vector3
var climb_to: Vector3
var muzzle: MeshInstance3D
var aim_blend: float = 0
var grip_hand: Node3D
var support_hand: Node3D
const HIP_FOV: float = 83.0
const AIM_FOV: float = 58.0
const HIP_RIFLE_POSITION = Vector3(0.22, -0.245, -0.40)

func _ready():
	collision_layer = 2
	collision_mask = 1|4
	floor_snap_length = 0.35
	shape = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.80
	shape.shape = capsule
	shape.position.y = 0.90
	add_child(shape)
	head = Node3D.new()
	add_child(head)
	head.position.y = eye_height
	camera = Camera3D.new()
	head.add_child(camera)
	camera.near = 0.025
	camera.far = 450
	camera.fov = 83
	hands = Node3D.new()
	camera.add_child(hands)
	rifle = Art.rifle(hands)
	grip_hand = Art.gauntlet(rifle,Vector3(0.031,-0.080,0.14),Vector3(-0.6,0,-0.3))
	support_hand = Art.gauntlet(rifle,Vector3(-0.022,-0.090,-0.40),Vector3(-0.9,0,0.2))
	grip_hand.scale = Vector3.ONE * 0.82
	support_hand.scale = Vector3.ONE * 0.82
	rifle.position = HIP_RIFLE_POSITION
	blade = Art.sword(hands)
	Art.gauntlet(blade,Vector3(0,0.01,0.02),Vector3(0,0,0))
	fists = Node3D.new()
	hands.add_child(fists)
	Art.gauntlet(fists,Vector3(-0.22,0,0),Vector3(-0.65,0,0.2))
	Art.gauntlet(fists,Vector3(0.22,-0.025,0),Vector3(-0.65,0,-0.2))
	shovel=Art.shovel(hands)
	var glow = Art.material(Color("ffe7aa")).duplicate()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle = Art.sphere(rifle,0.035,rifle.get_node("Muzzle").position,glow)
	muzzle.visible = false
	# Visible legs, breastplate and carried weapons; equipment is physically stowed.
	body_model = Art.knight(self)
	# Hide the world model's head from the first-person camera using layer two.
	set_model_layers(body_model,2)
	camera.cull_mask = 1
	var steel = Art.material(Color("788684"),0.72,0.36)
	for x in [-0.15,0.15]:
		Art.cylinder(self,0.10,0.60,Vector3(x,0.43,0.02),steel,0.13)
		Art.box(self,Vector3(0.20,0.14,0.34),Vector3(x,0.09,-0.08),steel)
	slung = Art.rifle(self)
	slung.position = Vector3(0.26,1.04,0.28)
	slung.rotation = Vector3(PI/2,0,-0.18)
	scabbard = Node3D.new()
	add_child(scabbard)
	scabbard.position = Vector3(-0.34,0.97,0.08)
	scabbard.rotation.z = -2.93
	Art.box(scabbard,Vector3(0.079,0.98,0.034),Vector3(0,0.58,0),Art.material(Color("473a2b")))
	sheathed = Art.sword(scabbard)
	for entry in [[rifle,"rifle"],[slung,"rifle"],[blade,"sword"],[sheathed,"sword"],[shovel,"shovel"]]:
		var hitbox=EquipmentHitbox.new()
		hitbox.wielder=self
		hitbox.item=entry[1]
		entry[0].add_child(hitbox)
		equipment_boxes.append(hitbox)
	select_weapon(0)

func set_model_layers(node: Node, layers: int):
	if node is VisualInstance3D:
		node.layers = layers
	for child in node.get_children():
		set_model_layers(child,layers)

func _unhandled_input(event):
	if game.phase != "playing":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Preserve screen-space control when aiming magnifies the scene.
		var aim_sensitivity = tan(deg_to_rad(camera.fov * 0.5)) / tan(deg_to_rad(HIP_FOV * 0.5))
		rotate_y(-event.relative.x*sensitivity*aim_sensitivity)
		head.rotation.x = clampf(head.rotation.x-event.relative.y*sensitivity*aim_sensitivity,-1.35,1.35)
	if game.player_mounted:
		rotation.y=PI+clampf(wrapf(rotation.y-PI,-PI,PI),-1.20,1.20)
		head.rotation.x=clampf(head.rotation.x,-0.25,0.28)
		if event.is_action_pressed("interact"):game.leave_mg()
		return
	if event.is_action_pressed("weapon_demolition"):select_weapon(4)
	if event.is_action_pressed("detonate"):game.demolition.detonate()
	if weapon==4 and event.is_action_pressed("aim"):game.demolition.deploy(true)
	if event.is_action_pressed("weapon_sword"):
		select_weapon(0)
	if event.is_action_pressed("weapon_rifle"):
		select_weapon(1)
	if event.is_action_pressed("weapon_fists"):
		select_weapon(2)
	if event.is_action_pressed("weapon_shovel"):
		select_weapon(3)
	if event.is_action_pressed("attack"):
		if weapon == 1: attack()
		elif weapon == 3: dig_stroke()
		elif weapon == 4: game.demolition.deploy(false)
		else:
			holding_attack = true
			power_hold = 0
	if event.is_action_released("attack") and weapon in [0,2] and holding_attack:
		holding_attack = false
		attack(power_hold)
		power_hold = 0
	if event.is_action_pressed("prone"):
		prone = not prone
	if event.is_action_pressed("reload"):
		reload_weapon()
	if event.is_action_pressed("interact"):
		game.interact()
	if event.is_action_pressed("grenade"):
		if grenades > 0:
			grenades -= 1
			game.throw_grenade(camera.global_position,-camera.global_basis.z)
		else:
			game.toast("No grenades. The outpost has a supply crate.",2)
	if event.is_action_pressed("jump"):
		prone = false
		if climbing<=0 and not try_mantle() and is_on_floor():
			velocity.y = 6.2

func _physics_process(delta):
	if game.phase != "playing":
		return
	if game.player_mounted:
		camera.fov=lerpf(camera.fov,58.0 if Input.is_action_pressed("aim") else HIP_FOV,delta*10)
		return
	if climbing > 0:
		climbing = maxf(0,climbing-delta)
		global_position = climb_from.lerp(climb_to,smoothstep(0,1,1-climbing/0.48))
		return
	cooldown = maxf(0,cooldown-delta)
	if weapon==3 and Input.is_action_pressed("attack") and cooldown==0:dig_stroke()
	if reload_time > 0:
		reload_time = maxf(0,reload_time-delta)
		if reload_time == 0:
			var rounds = mini(6-ammo,reserve)
			ammo += rounds
			reserve -= rounds
	if holding_attack: power_hold = minf(1.2,power_hold+delta)
	attack_time = maxf(0,attack_time-delta)
	if attack_pending and attack_time < (0.35 if weapon == 0 else 0.22):
		attack_pending = false
		melee_hit()
	var input_dir = Input.get_vector("move_left","move_right","move_forward","move_back")
	crouched = Input.is_action_pressed("crouch") and not prone
	aiming = Input.is_action_pressed("aim") and weapon == 1 and reload_time <= 0
	is_sprinting = Input.is_action_pressed("sprint") and input_dir.y < -0.1 and stamina > 3 and not crouched and not prone and not aiming
	is_charging = is_sprinting and weapon in [0,2] and Input.is_action_pressed("aim") and stamina > 5
	var speed = 11.4 if is_charging else (7.8 if is_sprinting else (1.15 if prone else (2.3 if crouched else 4.9)))
	if aiming:
		speed = 2.8
	stamina = clampf(stamina+(-28 if is_charging else (-19 if is_sprinting else 15))*delta,0,100)
	var direction = transform.basis*Vector3(input_dir.x,0,input_dir.y)
	velocity.x = move_toward(velocity.x,direction.x*speed,25*delta)
	velocity.z = move_toward(velocity.z,direction.z*speed,25*delta)
	if not is_on_floor():
		velocity.y -= 20*delta
	elif direction.length()>0.1:
		step_over_rubble(direction.normalized())
	move_and_slide()
	if global_position.y< -26:
		game.defeat()
	# Crouch adjusts both viewpoint and the hittable collision volume.
	eye_height = lerpf(eye_height,0.51 if prone else (1.12 if crouched else 1.68),delta*12)
	shape.shape.height = 0.66 if prone else (1.22 if crouched else 1.80)
	shape.position.y = shape.shape.height*0.5
	var moving = Vector2(velocity.x,velocity.z).length()
	bob += delta*moving*1.8
	head.position.y = eye_height+sin(bob)*lerpf(0.027,0.006,aim_blend)*minf(moving,1)
	var desired_lean = Input.get_axis("lean_left","lean_right")
	var side = global_basis.x*desired_lean*0.35
	var from = global_position+Vector3(0,eye_height,0)
	var ray = PhysicsRayQueryParameters3D.create(from,from+side,1)
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		desired_lean = 0
	lean = lerpf(lean,desired_lean,delta*9)
	camera.position.x = lean*0.29
	camera.rotation.z = -lean*0.13
	if is_on_floor() and moving > 0.5:
		step_clock += delta*moving
		if step_clock > (2.7 if is_sprinting else 2.1):
			step_clock = 0
			game.sounds.play("step",-14 if crouched else -9,randf_range(0.85,1.1))
			game.emit_noise(global_position,1.6 if prone else (3.0 if crouched else (14.0 if is_sprinting else 7.0)),1,"footstep")
	if absf(position.x)>74 or position.z < -85 or position.z > 61:
		game.toast("The outpost lies within the rocky basin.",2)
		position.x = clampf(position.x,-74,74)
		position.z = clampf(position.z,-85,61)

func _process(delta):
	if game.phase != "playing" or game.player_mounted: return
	# Cosmetic movement follows rendered frames, not the fixed physics tick rate.
	recoil = move_toward(recoil,0,delta*2.8)
	camera.rotation.x = recoil*0.020
	update_view(delta)

func update_view(delta):
	aim_blend = move_toward(aim_blend,1.0 if aiming else 0.0,delta/0.20)
	var aim_weight = smoothstep(0,1,aim_blend)
	var target_fov = lerpf(96.0 if is_charging else (88.0 if is_sprinting else HIP_FOV),AIM_FOV,aim_weight)
	camera.fov = lerpf(camera.fov,target_fov,1-exp(-15*delta))
	var motion = clampf(Vector2(velocity.x,velocity.z).length()/4.9,0,1)
	var sway = sin(bob)*0.008*motion
	var sight = rifle.get_node("SightLine") as Marker3D
	var aim_position = Vector3(-sight.position.x,-sight.position.y,-0.48)
	var hip_position = HIP_RIFLE_POSITION+Vector3(sin(bob*0.5)*0.004*motion,sway,0)
	rifle.position = hip_position.lerp(aim_position,aim_weight)+Vector3(0,-recoil*0.004,recoil*0.027)
	rifle.rotation = Vector3(recoil*0.045,0,lerpf(-0.10 if is_sprinting else 0.0,0.0,aim_weight))
	var bolt = rifle.get_node("Bolt") as Node3D
	var clip = rifle.get_node("ReloadClip") as Node3D
	bolt.rotation = Vector3.ZERO
	bolt.position = Vector3(0,0.038,0.045)
	grip_hand.position = Vector3(0.031,-0.080,0.14)
	support_hand.position = Vector3(-0.022,-0.090,-0.40)
	support_hand.rotation = Vector3(-0.9,0,0.2)
	clip.visible = false
	if reload_time > 0:
		var progress = clampf(1-reload_time/2.3,0,1)
		var lifted = smoothstep(0,0.16,progress)*(1-smoothstep(0.82,1,progress))
		rifle.position += Vector3(0,-0.10,0.01)*lifted
		rifle.rotation.z = -0.23*lifted
		bolt.rotation.z = 0.95*lifted
		bolt.position.z += 0.075*lifted
		clip.visible = progress > 0.28 and progress < 0.72
		clip.position = Vector3(0,lerpf(0.17,0.012,smoothstep(0.33,0.71,progress)),-0.025)
		var reaching = smoothstep(0.20,0.34,progress)*(1-smoothstep(0.68,0.88,progress))
		support_hand.position = support_hand.position.lerp(Vector3(-0.055,clip.position.y-0.045,-0.04),reaching)
		support_hand.rotation = support_hand.rotation.lerp(Vector3(-0.35,0,-0.75),reaching)
	elif weapon == 1 and cooldown > 0 and cooldown <= 1.15 and ammo >= 0:
		var progress = clampf(1-cooldown/1.15,0,1)
		var lift = smoothstep(0.16,0.32,progress)*(1-smoothstep(0.82,0.96,progress))
		var pulled = smoothstep(0.33,0.52,progress)*(1-smoothstep(0.60,0.80,progress))
		bolt.rotation.z = lift*0.95
		bolt.position.z += pulled*0.075
		grip_hand.position = grip_hand.position.lerp(Vector3(0.079,0.0,0.12+pulled*0.075),lift)
	blade.position = Vector3(0.39,-0.52+sway,-0.65)
	blade.rotation = Vector3(-0.16,0,-0.15)
	if holding_attack:
		blade.rotation.z += minf(power_hold,1)*0.85
		blade.rotation.x += minf(power_hold,1)*0.4
	if weapon == 0 and attack_time > 0:
		var progress = 1-attack_time/0.58
		blade.rotation.x -= sin(progress*PI)*1.25
		blade.rotation.z -= sin(progress*PI)*1.40
		blade.position.x -= sin(progress*PI)*0.4
	fists.position = Vector3(0,-0.27+sway,-0.49)
	if weapon == 2 and attack_time > 0:
		fists.get_child(1).position.z = -sin((1-attack_time/0.39)*PI)*0.38
	else:
		fists.get_child(1).position.z = 0
	if is_sprinting:
		blade.rotation.x += 0.3
	shovel.position=Vector3(0.37,-0.56+sway,-0.67)
	shovel.rotation=Vector3(-0.15,0,-0.25)
	if weapon==3 and cooldown>0:
		shovel.rotation.x-=sin(clampf(1-cooldown/0.65,0,1)*PI)*1.0

func select_weapon(slot: int):
	if slot==4 and game.demolition and game.demolition.carried==0 and not is_instance_valid(game.demolition.active):
		game.toast("Find demolition supplies in the village engineer's store.",3)
		return
	if game.demolition:
		game.demolition.detonator.hide()
		game.demolition.satchel.hide()
	if slot==0 and sword_health<=0:
		game.toast("Your sword is broken. Use your gauntlets or another weapon.",2)
		return
	if slot==3 and (not has_shovel or shovel_health<=0):
		game.toast("Search the sentry's pockets for an entrenching tool.",2)
		return
	if slot == 1 and not has_rifle:
		if game: game.toast("The isolated sentry carries a rifle.",2)
		return
	weapon = slot
	attack_time = 0
	attack_pending = false
	holding_attack = false
	power_hold = 0
	reload_time = 0
	aiming = false
	aim_blend = 0
	if not is_instance_valid(rifle): return
	rifle.visible = slot == 1
	blade.visible = slot == 0
	fists.visible = slot == 2
	shovel.visible = slot == 3
	slung.visible = has_rifle and slot != 1
	sheathed.visible = slot != 0 and sword_health>0
	for box in equipment_boxes:box.set_active(box.get_parent().visible)

func attack(power: float = 0):
	if cooldown > 0 or climbing > 0 or reload_time > 0: return
	strike_power = 1.0 + clampf(power,0,1.2)*1.2 + (0.7 if is_charging else 0)
	if weapon == 1:
		if ammo == 0:
			game.sounds.play("bolt",-15)
			game.toast("Empty. R to reload." if reserve > 0 else "Empty. Loot ammunition or draw your sword.",3)
			cooldown = 0.3
			return
		ammo -= 1
		shot_count += 1
		cooldown = 1.15
		recoil = 1
		game.sounds.play("rifle",-6)
		var start = camera.global_position
		var dir = -camera.global_basis.z
		# At these prototype ranges a settled iron sight should hit its point of aim.
		var spread = 0.0 if aiming else 0.012
		dir += camera.global_basis.x*randf_range(-spread,spread)+camera.global_basis.y*randf_range(-spread,spread)
		var end = start+dir.normalized()*200
		var q = PhysicsRayQueryParameters3D.create(start,end,1|4|16)
		q.collide_with_areas=true
		q.exclude = shot_exclusions()
		var hit = get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			end = hit.position
			if hit.collider.has_method("receive_hit"):
				hit.collider.receive_hit(105,hit.position)
				game.hit_flash=0.2
			elif hit.collider.has_method("take_damage"):
				var is_head = hit.position.y-hit.collider.global_position.y > 1.49
				hit.collider.take_damage(105,is_head)
				hit_count += 1
				game.hit_flash = 0.23
			else:
				game.damage_environment(hit,42,0.27)
				game.impact(end,Color("c5b58a"))
		game.tracer(muzzle.global_position,end,Color("f0cd8e"))
		game.emit_noise(position,175,1,"gunshot")
		game.notify_projectile(start,end,1)
		muzzle.visible = true
		get_tree().create_timer(0.065).timeout.connect(func(): muzzle.visible = false)
		get_tree().create_timer(0.45).timeout.connect(func(): game.sounds.play("bolt",-14))
	else:
		attack_time = 0.58 if weapon == 0 else 0.39
		cooldown = attack_time
		attack_pending = true
		game.sounds.play("sword",-10,0.75 if weapon == 0 else 1.35)

func melee_hit():
	var closest = null
	var best = 3.05 if weapon == 0 else 2.20
	var origin = camera.global_position
	for enemy in game.enemies:
		if not enemy.alive: continue
		var target = enemy.global_position+Vector3(0,1.2,0)
		var dist = origin.distance_to(target)
		if dist > best: continue
		if (-camera.global_basis.z).dot((target-origin).normalized()) < 0.55: continue
		var q = PhysicsRayQueryParameters3D.create(origin,target,1|4)
		q.exclude = [get_rid()]
		var hit = get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.collider == enemy:
			closest = enemy
			best = dist
	if closest:
		closest.take_damage((105 if weapon == 0 else 42)*strike_power)
		game.hit_flash = 0.2
		game.sounds.play("clang",-15,0.7)
		game.emit_noise(position,10,1,"melee")
	else:
		var ray=PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*2.5,1|16)
		ray.collide_with_areas=true
		ray.exclude=shot_exclusions()
		var impact=get_world_3d().direct_space_state.intersect_ray(ray)
		if not impact.is_empty():
			if impact.collider.has_method("receive_hit"):impact.collider.receive_hit(60*strike_power,impact.position)
			else:game.damage_environment(impact,(24 if weapon==0 else 13)*strike_power,0.38)
			game.sounds.play("clang",-13)

func shot_exclusions() -> Array[RID]:
	var result: Array[RID]=[get_rid()]
	for box in equipment_boxes:
		if is_instance_valid(box):result.append(box.get_rid())
	return result

func receive_equipment_damage(item: String, amount: float):
	if game.phase!="playing":return
	match item:
		"rifle":
			rifle_health=maxf(0,rifle_health-amount)
			if rifle_health==0 and has_rifle:
				reserve+=ammo
				ammo=0
				has_rifle=false
				if weapon==1:select_weapon(0 if sword_health>0 else 2)
				rifle.hide()
				slung.hide()
				game.toast("RIFLE BROKEN  •  Recover an intact weapon from another soldier.",4)
		"sword":
			sword_health=maxf(0,sword_health-amount)
			if sword_health==0:
				if weapon==0:select_weapon(2)
				blade.hide()
				sheathed.hide()
				game.toast("Your sword has broken. Steel gauntlets it is.",3)
		"shovel":
			shovel_health=maxf(0,shovel_health-amount)
			if shovel_health==0:
				has_shovel=false
				if weapon==3:select_weapon(2)
				shovel.hide()
	for box in equipment_boxes:box.set_active(box.get_parent().visible)
	game.sounds.play("clang",-7)

func dig_stroke():
	if cooldown>0 or not has_shovel:return
	cooldown=0.65
	var ray=PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3.0,1|16)
	ray.collide_with_areas=true
	ray.exclude=shot_exclusions()
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():return
	if hit.collider.has_method("damage_at") and hit.collider.material_kind=="soil":
		game.world.dig(hit.position)
		game.sounds.play("step",-7,0.7)
	else:
		game.damage_environment(hit,22,0.35)
		game.sounds.play("clang",-13)
	game.impact(hit.position,Color("9b8769"))

func step_over_rubble(direction: Vector3):
	var space=get_world_3d().direct_space_state
	var low=global_position+Vector3(0,0.16,0)
	var ahead=direction*0.55
	var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(low,low+ahead,1))
	if hit.is_empty():return
	var top=space.intersect_ray(PhysicsRayQueryParameters3D.create(global_position+ahead+Vector3(0,0.55,0),global_position+ahead+Vector3(0,-0.05,0),1))
	if top.is_empty() or top.normal.y<0.7:return
	var lift=top.position.y-global_position.y
	if lift>0.025 and lift<0.40:
		var clear=PhysicsRayQueryParameters3D.create(top.position+Vector3(0,0.06,0),top.position+Vector3(0,1.85,0),1)
		if space.intersect_ray(clear).is_empty():global_position.y+=lift+0.025

func reload_weapon():
	if weapon != 1 or reload_time > 0 or ammo == 6: return
	if reserve == 0:
		game.toast("No spare ammunition. %d / 6 rounds remain." % ammo,2.5)
		return
	reload_time = 2.3
	cooldown = 2.3
	game.sounds.play("reload",-10)

func take_damage(amount: float, source: Vector3, kind: String = "rifle"):
	if game.phase != "playing": return
	# Plate protects against blows; twentieth-century rifle rounds still penetrate it.
	health = maxf(0,health-amount*(0.4 if kind=="melee" else 1.0))
	game.damage_flash = 0.55
	game.last_damage_direction = (source-global_position).normalized()
	game.sounds.play("hit",-6)
	if health <= 0: game.defeat()

func try_mantle() -> bool:
	var direction = -global_basis.z
	var low = global_position+Vector3(0,0.66,0)
	var q = PhysicsRayQueryParameters3D.create(low,low+direction*1.25,1)
	var hit = get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty(): return false
	var probe = hit.position+direction*0.30
	probe.y = global_position.y+2.7
	var down = PhysicsRayQueryParameters3D.create(probe,probe-Vector3(0,2.9,0),1)
	var top = get_world_3d().direct_space_state.intersect_ray(down)
	if top.is_empty(): return false
	var height = top.position.y-global_position.y
	if height < 0.2 or height > 1.75: return false
	var clearance = PhysicsRayQueryParameters3D.create(top.position+Vector3(0,0.05,0),top.position+Vector3(0,1.9,0),1)
	if not get_world_3d().direct_space_state.intersect_ray(clearance).is_empty(): return false
	climb_from = global_position
	climb_to = top.position+Vector3(0,0.06,0)
	climbing = 0.48
	velocity = Vector3.ZERO
	return true
