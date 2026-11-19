## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/player.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
extends CharacterBody3D

const Art = preload("res://scripts/art.gd")
const EquipmentHitbox=preload("res://scripts/equipment_hitbox.gd")

## The Game node (game.gd): phase, enemies, sounds, toasts, interaction.
var game

## First-person camera; its cull mask hides the player's own body model.
var camera: Camera3D

## Pivot at eye height; pitch (look up/down) is applied here, yaw on the body.
var head: Node3D

## Child of the camera that holds all view models so they move with the view.
var hands: Node3D

## First-person rifle view model (Art.rifle).
var rifle: Node3D

## First-person sword view model.
var blade: Node3D

## First-person pair of gauntlets.
var fists: Node3D

## First-person entrenching tool.
var shovel: Node3D

## True once the shovel has been looted from the sentry.
var has_shovel: bool=false

## Durability of the rifle; at 0 it breaks (see receive_equipment_damage).
var rifle_health: float=100

## Durability of the sword.
var sword_health: float=140

## Durability of the shovel.
var shovel_health: float=110

## Hit-area nodes on carried items; toggled so only visible items can be shot.
var equipment_boxes: Array=[]

## Third-person knight model (visible legs, shown only on layer 2).
var body_model: Node3D

## Rifle model slung on the back when another weapon is out.
var slung: Node3D

## Scabbard node on the hip.
var scabbard: Node3D

## Sword model in the scabbard.
var sheathed: Node3D

## Collision capsule; its height changes with crouch and prone.
var shape: CollisionShape3D

## Health cap from player_stats.gd.
var max_health:float=preload("res://scripts/player_stats.gd").MAX_HEALTH

## Current hit points.
var health:float=max_health

## Always 100 now: sprinting and charging no longer cost stamina (kept for the HUD bar).
var stamina: float = 100

## Rounds loaded in the rifle (6 max).
var ammo: int = 0

## Spare rounds carried.
var reserve: int = 0

## True once a rifle has been looted.
var has_rifle: bool = false

## Current weapon slot (see class comment).
var weapon: int = 0 # 0 sword, 1 rifle, 2 fists

## Number of grenades carried.
var grenades: int = 0

## Current eye height in metres; eased between standing 1.68, crouched 1.12, prone 0.51.
var eye_height: float = 1.68

## True while sprinting forward (not crouched, prone or aiming).
var is_sprinting: bool = false

## True while the crouch key is held (and not prone).
var crouched: bool = false

## Toggled by the prone key; cancelled by jumping.
var prone: bool = false

## True while sprinting with a melee weapon and holding aim: a shoulder
## charge that adds damage (see attack()).
var is_charging: bool = false

## Seconds the attack button has been held for a heavy blow, capped at 1.2.
var power_hold: float = 0

## True while the button is held for a charged melee swing.
var holding_attack: bool = false

## Damage multiplier for the current melee swing: 1 + 1.2 x hold + 0.7 if charging.
var strike_power: float = 1

## Seconds left on a reload (2.3 s total).
var reload_time: float = 0

## True while aiming the rifle down sights.
var aiming: bool = false

## Seconds until the next attack, dig or bolt cycle is allowed.
var cooldown: float = 0

## Remaining swing animation time; 0 when idle.
var attack_time: float = 0

## True from swing start until the hit is resolved mid-swing.
var attack_pending: bool = false

## Head-bob phase, advanced by distance moved.
var bob: float = 0

## Accumulated movement used to time footstep sounds.
var step_clock: float = 0

## Smoothed lean amount -1..1.
var lean: float = 0

## Rifle kick, 1 on firing and decaying to 0; drives view-model and camera kick.
var recoil: float = 0

## Mouse look radians per pixel.
var sensitivity: float = 0.0021

## Rifle shots fired (shown on the end screen).
var shot_count: int = 0

## Rifle hits on enemies.
var hit_count: int = 0

## Seconds left of a mantle animation; 0 when not climbing.
var climbing: float = 0

## Start of the current mantle path.
var climb_from: Vector3

## End of the current mantle path.
var climb_to: Vector3

## Muzzle-flash sphere on the first-person rifle.
var muzzle: MeshInstance3D

## 0 hip .. 1 aiming, eased over 0.2 s.
var aim_blend: float = 0

## Gauntlet on the rifle's trigger grip.
var grip_hand: Node3D

## Gauntlet that supports the rifle forend and reaches for the clip on reload.
var support_hand: Node3D

## Field of view (degrees) when not aiming.
const HIP_FOV: float = 83.0

## Field of view when aiming down sights; lower for magnification.
const AIM_FOV: float = 58.0

## Rifle position in the camera's local space when held at the hip.
const HIP_RIFLE_POSITION = Vector3(0.22, -0.245, -0.40)

## Godot lifecycle hook: builds the capsule, camera rig, all first-person
## view models (rifle, sword, fists, shovel), the visible body model with
## its legs, slung rifle and scabbard, hit areas, and equips the sword.
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

	# Very close near plane (2.5 cm) so the rifle and hands do not clip when held close to walls.
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

	# Camera sees only layer 1, so the body model (layer 2) never blocks the view.
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

	# Every carried item gets a hit area (rifle and slung rifle share the "rifle" kind).
	for entry in [[rifle,"rifle"],[slung,"rifle"],[blade,"sword"],[sheathed,"sword"],[shovel,"shovel"]]:
		var hitbox=EquipmentHitbox.new()
		hitbox.wielder=self
		hitbox.item=entry[1]
		entry[0].add_child(hitbox)
		equipment_boxes.append(hitbox)
	select_weapon(0)

## Sets the render layer mask on every VisualInstance3D under `node`.
## [param layers] bit mask (2 = layer 2 only).
func set_model_layers(node: Node, layers: int):
	if node is VisualInstance3D:
		node.layers = layers
	for child in node.get_children():
		set_model_layers(child,layers)

## Handles mouse look and one-shot key presses while playing.
## Mouse-look speed scales with the zoom (tangent ratio of the FOVs), so
## aiming feels equally fast on screen. While on the mounted gun, yaw is
## limited to +-1.2 rad and pitch to -0.25..0.28 rad, and `interact` dismounts.
## [param event] input event; ignored unless game.phase is "playing".
func _unhandled_input(event):
	if game.phase != "playing":
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Preserve screen-space control when aiming magnifies the scene.
		# Keeps on-screen turn speed constant: the narrower the FOV, the slower the turn.
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

	# Left-click means: fire the rifle, swing the shovel, throw/place the
	# satchel, or begin charging a melee blow (released later to strike).
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

	# Jump clears prone; a mantle is tried first, a jump only from the floor (6.2 m/s).
	if event.is_action_pressed("jump"):
		prone = false
		if climbing<=0 and not try_mantle() and is_on_floor():
			velocity.y = 6.2

## Per-physics-tick movement and state: reload, melee timing, crouch/sprint/
## aim flags, walking with acceleration, gravity, leaning, footsteps and
## world bounds. Restores the camera offset first (see ViewSmoothing).
## [param delta] physics step in seconds.
func _physics_process(delta):
	if game.phase != "playing":
		return

	# On the machine gun: only the zoom is updated; movement is locked.
	if game.player_mounted:
		camera.fov=lerpf(camera.fov,58.0 if Input.is_action_pressed("aim") else HIP_FOV,delta*10)
		return

	# Mantling follows a fixed 0.48 s smoothstep path; all input is ignored meanwhile.
	if climbing > 0:
		climbing = maxf(0,climbing-delta)
		global_position = climb_from.lerp(climb_to,smoothstep(0,1,1-climbing/0.48))
		return
	cooldown = maxf(0,cooldown-delta)
	if weapon==3 and Input.is_action_pressed("attack") and cooldown==0:dig_stroke()

	# When the reload ends, top up the magazine to 6 from the reserve.
	if reload_time > 0:
		reload_time = maxf(0,reload_time-delta)
		if reload_time == 0:
			var rounds = mini(6-ammo,reserve)
			ammo += rounds
			reserve -= rounds
	if holding_attack: power_hold = minf(1.2,power_hold+delta)
	attack_time = maxf(0,attack_time-delta)

	# The swing connects partway through the animation (0.35 s left for the
	# sword, 0.22 s for fists), not at the moment of the click.
	if attack_pending and attack_time < (0.35 if weapon == 0 else 0.22):
		attack_pending = false
		melee_hit()
	var input_dir = Input.get_vector("move_left","move_right","move_forward","move_back")
	crouched = Input.is_action_pressed("crouch") and not prone
	aiming = Input.is_action_pressed("aim") and weapon == 1 and reload_time <= 0
	is_sprinting = Input.is_action_pressed("sprint") and input_dir.y < -0.1 and stamina > 3 and not crouched and not prone and not aiming
	is_charging = is_sprinting and weapon in [0,2] and Input.is_action_pressed("aim") and stamina > 5

	# Speeds in m/s: charge 11.4, sprint 7.8, prone 1.15, crouch 2.3, walk 4.9
	# and 2.8 when aiming.
	var speed = 11.4 if is_charging else (7.8 if is_sprinting else (1.15 if prone else (2.3 if crouched else 4.9)))
	if aiming:
		speed = 2.8
	stamina = clampf(stamina+(-28 if is_charging else (-19 if is_sprinting else 15))*delta,0,100)
	var direction = transform.basis*Vector3(input_dir.x,0,input_dir.y)

	# Acceleration of 25 m/s^2 gives snappy but not instant movement.
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

	# Lean is cancelled if a wall is within 0.35 m on that side, so the camera
	# cannot poke through geometry.
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

			# Footstep noise radius lets enemies hear movement: prone 1.6 m, crouch 3,
			# sprint 14, walk 7 (team 1 = player's side).
			game.emit_noise(global_position,1.6 if prone else (3.0 if crouched else (14.0 if is_sprinting else 7.0)),1,"footstep")

	# Keep the player inside the playable basin and tell them why.
	if absf(position.x)>74 or position.z < -85 or position.z > 61:
		game.toast("The outpost lies within the rocky basin.",2)
		position.x = clampf(position.x,-74,74)
		position.z = clampf(position.z,-85,61)

## Per-render-frame cosmetic update: recoil decay and view-model animation.
## [param delta] frame time in seconds.
func _process(delta):
	if game.phase != "playing" or game.player_mounted: return
	# Cosmetic movement follows rendered frames, not the fixed physics tick rate.
	recoil = move_toward(recoil,0,delta*2.8)
	camera.rotation.x = recoil*0.020
	update_view(delta)

## Positions and animates the first-person view models: FOV changes for
## sprint (88), charge (96) and aim, rifle sway, aim alignment of the sight
## line to screen centre, reload and bolt-cycle poses, sword swing/charge
## poses, fist punch and shovel swing.
## [param delta] frame time in seconds.
func update_view(delta):
	aim_blend = move_toward(aim_blend,1.0 if aiming else 0.0,delta/0.20)
	var aim_weight = smoothstep(0,1,aim_blend)
	var target_fov = lerpf(96.0 if is_charging else (88.0 if is_sprinting else HIP_FOV),AIM_FOV,aim_weight)
	camera.fov = lerpf(camera.fov,target_fov,1-exp(-15*delta))
	var motion = clampf(Vector2(velocity.x,velocity.z).length()/4.9,0,1)
	var sway = sin(bob)*0.008*motion
	var sight = rifle.get_node("SightLine") as Marker3D

	# When aiming, the rifle is moved so its SightLine marker sits on the
	# camera axis: that is what makes the iron sights usable.
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

	# Reload animation phases over 2.3 s: lift the rifle, bring the clip in
	# with the support hand, then lower; each smoothstep window is one phase.
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

## Switches to a weapon slot after validating it (satchel needs supplies,
## sword and shovel must be intact, rifle and shovel must have been found),
## resets all attack/aim state and shows only the matching view model.
## [param slot] 0 sword, 1 rifle, 2 fists, 3 shovel, 4 satchel.
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

	# Every state flag is reset so a half-finished swing, charge or reload
	# cannot leak into the new weapon.
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

## Starts an attack with the current weapon.
## Rifle: needs a round, then fires a hitscan ray (200 m, layers world, AI
## team 0 and equipment) with 105 damage to enemies (head shot if the hit is
## above 1.49 m on the target), or 42 damage to the environment; 2 s bolt
## cooldown; sets recoil; makes a 175 m noise.
## Sword and fists: starts the swing animation; damage is applied later by
## melee_hit() when the swing connects.
## [param power] seconds of charge (0..1.2) used to scale melee damage.
func attack(power: float = 0):
	# Physics & Balance Invariants:
	# - Verifies ammunition availability and cyclic fire rate cooldown timer.
	# - Applies physical impulse kickback to viewmodel and emits spatial 3D gunfire acoustics.
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

## Resolves a sword or fist blow: finds the closest living enemy in front
## (range 3.05 m sword, 2.2 m fists, within a cone dot > 0.55) with a clear ray;
## deals 105 (sword) or 42 (fists) times strike_power. If nobody is hit it
## damages whatever is in reach (walls, doors, equipment) instead.
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

## RIDs a shot must ignore: the player's own body and all carried
## equipment hit areas, so shooting never hits yourself.
func shot_exclusions() -> Array[RID]:
	var result: Array[RID]=[get_rid()]
	for box in equipment_boxes:
		if is_instance_valid(box):result.append(box.get_rid())
	return result

## Damage to carried gear forwarded by the Equipment hit areas.
## [param item] "rifle", "sword" or "shovel". [param amount] damage points.
## When an item reaches 0 durability it breaks: the rifle loses its ammunition
## to the reserve, the sword and shovel are removed, and the player is moved
## to a working weapon with a toast.
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

## One shovel stroke (0.65 s cooldown): digs soil within 3 m, or damages other
## breakables with 22 damage.
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

## Auto-steps over low obstacles (2.5 cm to 40 cm) in the walking direction
## so debris and rubble do not stop the player; requires headroom of 1.85 m
## and a walkable top surface (normal.y >= 0.7).
## [param direction] normalised horizontal movement direction.
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

## Starts a 2.3 s rifle reload if the rifle is out, not full (6) and spare
## ammunition exists; otherwise explains why with a toast.
func reload_weapon():
	if weapon != 1 or reload_time > 0 or ammo == 6: return
	if reserve == 0:
		game.toast("No spare ammunition. %d / 6 rounds remain." % ammo,2.5)
		return
	reload_time = 2.3
	cooldown = 2.3
	game.sounds.play("reload",-10)

## Applies damage to the player and ends the mission at 0 health.
## [param amount] hit points. [param source] world position of the attacker
## (stored for the damage-direction indicator). [param kind] "melee" attacks
## are reduced to 40% by the armour; rifle rounds are not reduced.
func take_damage(amount: float, source: Vector3, kind: String = "rifle"):
	if game.phase != "playing": return
	# Plate protects against blows; twentieth-century rifle rounds still penetrate it.
	health = maxf(0,health-amount*(0.4 if kind=="melee" else 1.0))
	game.damage_flash = 0.55
	game.last_damage_direction = (source-global_position).normalized()
	game.sounds.play("hit",-6)
	if health <= 0: game.defeat()

## Attempts to climb a ledge in front: a ray at knee height finds a wall
## within 1.25 m, then a downward ray finds its top. Allowed for heights
## between 0.2 m and 1.75 m with 1.9 m of clear headroom above. On success
## starts a 0.48 s climb animation and returns true.
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
