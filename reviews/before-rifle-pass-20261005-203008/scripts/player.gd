# ==============================================================================
# Program: player.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for player.gd.
# ==============================================================================
## First-person player controller for the desert mission (the knight).
##
## A CharacterBody3D that owns the camera rig, the four held items (rifle, sword, fists, shovel)
## plus the demolition satchel hooks, stance and stamina, melee charge, aiming and reload
## animation, and a visible body model for stowed equipment. The mission script (`game`) sets
## `game` and drives phases; this script reads input in `_unhandled_input`, simulates movement
## in `_physics_process` (fixed tick) and cosmetic motion in `_process` (every rendered frame).
## The Ardennes and Omaha players (ardennes/player.gd, omaha/player.gd) are separate scripts.
## NOTE: only the first part of this file (setup, input, movement, start of update_view) is
## documented in this pass.
extends CharacterBody3D

# Art helpers and the hitbox that lets bullets hit equipment.
const Art = preload("res://scripts/art.gd")

# Mission controller: phase, sounds, demolition, interaction and toast helpers.
var game

# Camera rig: the head pivot carries the camera; `hands` is a child of the camera so held items follow the view.
var camera: Camera3D
var head: Node3D
var hands: Node3D

# Held items: rifle, sword, fists, shovel (shown only for the selected weapon).
var rifle: Node3D
var blade: Node3D
var fists: Node3D

# Third-person body model (hidden from the camera), the slung rifle, scabbard and sheathed sword visuals.
var body_model: Node3D
var slung: Node3D
var scabbard: Node3D
var sheathed: Node3D

# Collision capsule; its height changes with the stance.
var shape: CollisionShape3D
var health: float = 100

# Stamina 0-100; drained by sprinting and charging, regained when walking.
var stamina: float = 100

# Rounds in the rifle and in reserve; has_rifle becomes true after the sentry's rifle is recovered.
var ammo: int = 0
var reserve: int = 0
var has_rifle: bool = false

# Selected weapon: 0 sword, 1 rifle, 2 fists (3 shovel and 4 demolition are handled in the code below).
var weapon: int = 0 # 0 sword, 1 rifle, 2 fists

# Grenades carried.
var grenades: int = 0

# Camera height in metres above the feet; eased between stand, crouch and prone values.
var eye_height: float = 1.68

# Stance and action flags set every physics tick from the inputs.
var is_sprinting: bool = false
var crouched: bool = false
var prone: bool = false

# Melee charge state: is_charging (sprint + aim), power_hold (0..1.2 s of held attack) and holding_attack.
var is_charging: bool = false
var power_hold: float = 0
var holding_attack: bool = false

# Multiplier for the next melee strike.
var strike_power: float = 1

# Seconds left of the reload (2.3 s animation in update_view).
var reload_time: float = 0

# Aim-down-sights state and cooldown until the next attack.
var aiming: bool = false
var cooldown: float = 0

# Melee swing timer and a flag that applies the hit part-way through the swing.
var attack_time: float = 0
var attack_pending: bool = false

# Cosmetic accumulators: walking bob phase, footstep timer, lean amount, recoil kick.
var bob: float = 0
var step_clock: float = 0
var lean: float = 0
var recoil: float = 0

# Mouse sensitivity in radians per pixel.
var sensitivity: float = 0.0021

# Shots fired and hits scored, for the end screen and tests.
var shot_count: int = 0
var hit_count: int = 0

# Mantle (ledge climb) state: seconds left and the start and end positions.
var climbing: float = 0
var climb_from: Vector3
var climb_to: Vector3

# Muzzle flash sphere.
var muzzle: MeshInstance3D

## Build the collider, camera rig, held items, body model and hitboxes.
func _ready():
	# Layer 2 = player; mask 1|4 = world and enemy bodies.
	collision_layer = 2
	collision_mask = 1|4
	floor_snap_length = 0.35
	# Capsule 0.32 m radius, 1.8 m tall; it shrinks while crouching or prone.
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
	# Camera: 2.5 cm near plane so the rifle does not clip, 450 m far plane (graphics.gd may reduce it), physics interpolation off because ViewSmoothing handles it.
	camera = Camera3D.new()
	head.add_child(camera)
	camera.near = 0.025
	camera.far = 450
	camera.fov = 83
	# Held items are children of the camera so they stay in view.
	hands = Node3D.new()
	camera.add_child(hands)
	rifle = Art.rifle(hands)
	Art.gauntlet(rifle,Vector3(0.035,-0.1,0.15),Vector3(-0.6,0,-0.3))
	Art.gauntlet(rifle,Vector3(-0.03,-0.10,-0.34),Vector3(-0.9,0,0.2))
	blade = Art.sword(hands)
	Art.gauntlet(blade,Vector3(0,0.01,0.02),Vector3(0,0,0))
	fists = Node3D.new()
	hands.add_child(fists)
	Art.gauntlet(fists,Vector3(-0.22,0,0),Vector3(-0.65,0,0.2))
	Art.gauntlet(fists,Vector3(0.22,-0.025,0),Vector3(-0.65,0,-0.2))
	# Unshaded warm muzzle flash.
	var glow = Art.material(Color("ffe7aa")).duplicate()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	muzzle = Art.sphere(rifle,0.07,Vector3(0,0.04,-1.06),glow)
	muzzle.visible = false
	# Visible legs, breastplate and carried weapons; equipment is physically stowed.
	# Visible legs, breastplate and carried weapons; equipment is physically stowed.
	body_model = Art.knight(self)
	# Hide the world model's head from the first-person camera using layer two.
	# Hide the world model's head from the first-person camera using layer two.
	set_model_layers(body_model,2)
	camera.cull_mask = 1
	# Legs and boots drawn on the player body (visible when looking down).
	var steel = Art.material(Color("788684"),0.72,0.36)
	for x in [-0.15,0.15]:
		Art.cylinder(self,0.10,0.60,Vector3(x,0.43,0.02),steel,0.13)
		Art.box(self,Vector3(0.20,0.14,0.34),Vector3(x,0.09,-0.08),steel)
	# Slung rifle and sheathed sword, shown when the other weapon is in hand.
	slung = Art.rifle(self)
	slung.position = Vector3(0.26,1.04,0.28)
	slung.rotation = Vector3(PI/2,0,-0.18)
	scabbard = Node3D.new()
	add_child(scabbard)
	scabbard.position = Vector3(-0.34,0.97,0.08)
	scabbard.rotation.z = -2.93
	Art.box(scabbard,Vector3(0.079,0.98,0.034),Vector3(0,0.58,0),Art.material(Color("473a2b")))
	sheathed = Art.sword(scabbard)
	# Start with the sword drawn.
	select_weapon(0)

## Set the render layer of a node and all of its descendants.
## @param node Subtree root. @param layers Layer bit mask.
func set_model_layers(node: Node, layers: int):
	if node is VisualInstance3D:
		node.layers = layers
	for child in node.get_children():
		set_model_layers(child,layers)

## Handle mouse look and key presses (only while the game phase is "playing").
func _unhandled_input(event):
	if game.phase != "playing":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x*sensitivity)
		head.rotation.x = clampf(head.rotation.x-event.relative.y*sensitivity,-1.35,1.35)
	if event.is_action_pressed("weapon_sword"):
		select_weapon(0)
	if event.is_action_pressed("weapon_rifle"):
		select_weapon(1)
	if event.is_action_pressed("weapon_fists"):
		select_weapon(2)
	if event.is_action_pressed("attack"):
		if weapon == 1: attack()
		else:
			holding_attack = true
			power_hold = 0
	if event.is_action_released("attack") and weapon != 1 and holding_attack:
		holding_attack = false
		attack(power_hold)
		power_hold = 0
	# Toggle prone, reload, interact and grenade. The grenade count is decremented before the throw call.
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
	if event.is_action_pressed("jump") and is_on_floor():
		prone = false
		if not try_mantle():
			velocity.y = 6.2

## Fixed-tick update: stance, movement, leaning, footsteps and basic bounds.
## @param delta Seconds per physics tick.
func _physics_process(delta):
	if game.phase != "playing":
		return
	# Mantling overrides movement: lerp from the start to the end position over 0.48 s.
	if climbing > 0:
		climbing = maxf(0,climbing-delta)
		global_position = climb_from.lerp(climb_to,smoothstep(0,1,1-climbing/0.48))
		return
	cooldown = maxf(0,cooldown-delta)
	# Reload completes: fill the rifle up to 6 rounds from reserve.
	if reload_time > 0:
		reload_time = maxf(0,reload_time-delta)
		if reload_time == 0:
			var rounds = mini(6-ammo,reserve)
			ammo += rounds
			reserve -= rounds
	# Hold-to-charge power grows up to 1.2 s.
	if holding_attack: power_hold = minf(1.2,power_hold+delta)
	attack_time = maxf(0,attack_time-delta)
	# Apply the melee hit part-way through the swing (0.35 s left for the sword, 0.22 s for others).
	if attack_pending and attack_time < (0.35 if weapon == 0 else 0.22):
		attack_pending = false
		melee_hit()
	# Input: move axes, crouch toggle, aim (only with the rifle and not while reloading), sprint (forward only, with stamina) and melee charge.
	var input_dir = Input.get_vector("move_left","move_right","move_forward","move_back")
	crouched = Input.is_action_pressed("crouch") and not prone
	aiming = Input.is_action_pressed("aim") and weapon == 1
	is_sprinting = Input.is_action_pressed("sprint") and input_dir.y < -0.1 and stamina > 3 and not crouched and not prone and not aiming
	is_charging = is_sprinting and weapon != 1 and Input.is_action_pressed("aim") and stamina > 5
	# Speeds in m/s: charge 11.4, sprint 7.8, prone 1.15, crouch 2.3, walk 4.9, aiming 2.8.
	var speed = 11.4 if is_charging else (7.8 if is_sprinting else (1.15 if prone else (2.3 if crouched else 4.9)))
	if aiming:
		speed = 2.8
	# Stamina: charging costs 28/s, sprinting 19/s, otherwise 15/s recovers.
	stamina = clampf(stamina+(-28 if is_charging else (-19 if is_sprinting else 15))*delta,0,100)
	var direction = transform.basis*Vector3(input_dir.x,0,input_dir.y)
	# 25 m/s^2 acceleration for responsive but not instant movement; gravity is 20 m/s^2.
	velocity.x = move_toward(velocity.x,direction.x*speed,25*delta)
	velocity.z = move_toward(velocity.z,direction.z*speed,25*delta)
	if not is_on_floor():
		velocity.y -= 20*delta
	move_and_slide()
	# Crouch adjusts both viewpoint and the hittable collision volume.
	# Crouch adjusts both viewpoint and the hittable collision volume.
	eye_height = lerpf(eye_height,0.51 if prone else (1.12 if crouched else 1.68),delta*12)
	shape.shape.height = 0.66 if prone else (1.22 if crouched else 1.80)
	shape.position.y = shape.shape.height*0.5
	# Head bob scales with speed and almost vanishes while aiming.
	var moving = Vector2(velocity.x,velocity.z).length()
	bob += delta*moving*1.8
	head.position.y = eye_height+sin(bob)*0.027*minf(moving,1)
	# Leaning: pushed by 0.35 m toward the side unless a wall is in the way, then smoothed.
	var desired_lean = Input.get_axis("lean_left","lean_right")
	var side = global_basis.x*desired_lean*0.35
	var from = global_position+Vector3(0,eye_height,0)
	var ray = PhysicsRayQueryParameters3D.create(from,from+side,1)
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		desired_lean = 0
	lean = lerpf(lean,desired_lean,delta*9)
	camera.position.x = lean*0.29
	camera.rotation.z = -lean*0.13
	recoil = move_toward(recoil,0,delta*2.8)
	camera.rotation.x = recoil*0.025
	camera.fov = lerpf(camera.fov,49 if aiming else (96 if is_charging else (88 if is_sprinting else 83)),delta*11)
	update_view(delta)
	# Footsteps: sound plus a noise event whose radius depends on stance (prone 1.6 m, crouch 3, sprint 14, walk 7 m) so quiet movement is stealthy.
	if is_on_floor() and moving > 0.5:
		step_clock += delta*moving
		if step_clock > (2.7 if is_sprinting else 2.1):
			step_clock = 0
			game.sounds.play("step",-14 if crouched else -9,randf_range(0.85,1.1))
	# Keep the player inside the rocky basin (x +/-74, z from -85 to 61).
	if absf(position.x)>74 or position.z < -85 or position.z > 61:
		game.toast("The outpost lies within the rocky basin.",2)
		position.x = clampf(position.x,-74,74)
		position.z = clampf(position.z,-85,61)

## Update camera zoom and weapon animation (sights, bob, recoil, reload, bolt cycle).
## @param delta Seconds.
func update_view(delta):
	var sway = sin(bob)*0.01
	var rifle_pos = Vector3(0,-0.096,-0.39) if aiming else Vector3(0.26,-0.27+sway,-0.54)
	rifle.position = rifle.position.lerp(rifle_pos,delta*13)
	rifle.position.z += recoil*0.02
	rifle.rotation.x = recoil*0.06
	# Reload animation: progress 0..1 over 2.3 s; the rifle tilts, the bolt opens, the clip appears and the support hand reaches for it in defined phases.
	if reload_time > 0:
		rifle.rotation.z = -0.32
		rifle.position.y -= 0.14
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
		rifle.rotation.z = -0.13
	elif reload_time <= 0:
		rifle.rotation.z = 0

func select_weapon(slot: int):
	if slot == 1 and not has_rifle:
		if game: game.toast("The isolated sentry carries a rifle.",2)
		return
	weapon = slot
	attack_time = 0
	attack_pending = false
	holding_attack = false
	power_hold = 0
	reload_time = 0
	if not is_instance_valid(rifle): return
	rifle.visible = slot == 1
	blade.visible = slot == 0
	fists.visible = slot == 2
	slung.visible = has_rifle and slot != 1
	sheathed.visible = slot != 0

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
		var spread = 0.0018 if aiming else 0.012
		dir += camera.global_basis.x*randf_range(-spread,spread)+camera.global_basis.y*randf_range(-spread,spread)
		var end = start+dir.normalized()*200
		var q = PhysicsRayQueryParameters3D.create(start,end,1|4)
		q.exclude = [get_rid()]
		var hit = get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			end = hit.position
			if hit.collider.has_method("take_damage"):
				var is_head = hit.position.y-hit.collider.global_position.y > 1.49
				hit.collider.take_damage(105,is_head)
				hit_count += 1
				game.hit_flash = 0.23
			else:
				game.impact(end,Color("c5b58a"))
		game.tracer(muzzle.global_position,end,Color("f0cd8e"))
		game.alert_near(position,65)
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
		game.alert_near(position,12)

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
	var probe = global_position+direction*1.45+Vector3(0,2.7,0)
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
