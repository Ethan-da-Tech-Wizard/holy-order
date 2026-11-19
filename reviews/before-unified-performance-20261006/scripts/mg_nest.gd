## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/mg_nest.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## A crew-served Breda Modello 37 machine-gun nest for the desert mission.
##
## Role: placed by world.gd/game.gd, which sets `game` first. One enemy
## "mg" soldier (or the player) can operate it. The nest owns the gun's
## state (rounds, reserve trays, health, cooldown) and firing rules; the
## operator only calls claim(), track(), try_fire() and release().
## Ammunition model: 20-round rigid feed trays; the box beside the gun holds
## three spare trays that are never refilled, so ammunition is finite and
## destroying the box removes the reserve.
## The gun can be shot to pieces: its Equipment hitbox forwards damage to
## receive_equipment_damage(), and at 0 health it stops working and ejects
## whoever is operating it.
extends Node3D

# Breda modello 37: 8 mm ammunition in 20-round rigid feed trays.
# The adjacent box is the sole reserve supply: three full trays, never refilled.
const Art=preload("res://scripts/art.gd")
const Equipment=preload("res://scripts/equipment_hitbox.gd")

## The Game node; supplies phase, player, sounds, fire_projectile(), emit_noise().
var game

## Rounds left in the tray on the gun (max 20).
var rounds: int=20

## Full trays left in the box; each reload uses one.
var spare_trays: int=3

## Counter of all shots (used by tests and the AI to assess activity).
var shots_fired: int=0

## Hit points of the gun (260); falls with equipment damage.
var health: float=260

## The actor (enemy or player) currently on the gun, or null.
var operator

## The turning part of the gun (receiver, barrel, sights); rotated by track().
var pivot: Node3D

## The destructible ammunition box beside the gun.
var box

## Visual tray nodes in the box; one is hidden for each tray used.
var trays: Array=[]

## The equipment hit area on the gun, so bullets can damage it.
var hitbox

## Seconds until the gun may fire again; may go slightly negative to carry
## over timing between frames so the cyclic rate stays accurate.
var cooldown: float=0

## Seconds left on an in-progress tray change (3.2 s) or 0.
var reload_time: float=0

## Rounds fired in the current burst; AI gunners pause after 5.
var burst_count: int=0

## Marker at the barrel tip, where shots and the flash originate.
var muzzle: Marker3D

## Muzzle flash sphere, shown for 0.04 s per shot.
var flash: MeshInstance3D

## Godot lifecycle hook: builds the whole model procedurally: tripod, gun body
## with cooling rings and sights, muzzle marker and flash, hit area, and the
## ammunition box with three trays of 20 visible cartridges each.
func _ready():
	var metal=Art.material(Color("404742"),0.72,0.43)
	var wood=Art.material(Color("635c43"))
	# Low tripod behind a U-shaped sandbag emplacement, open at the rear.
	# Each leg is tilted from the ground point toward the gun's pivot.
	for p in [Vector3(-0.7,0,0.4),Vector3(0.7,0,0.4),Vector3(0,0,-1)]:
		var leg=Art.solid(self,Vector3(0.085,0.9,0.085),p*0.5+Vector3(0,0.42,0),metal,0,"metal")
		leg.quaternion=Quaternion(Vector3.UP,(Vector3(0,0.9,0)-p).normalized())
	pivot=Node3D.new()
	add_child(pivot)
	pivot.position.y=1.15

	# The barrel is modelled along -Z; this half-turn makes it face the nest's
	# +Z (front). The gunner stands behind it at -Z (see operator_position).
	pivot.rotation.y=PI
	Art.solid(pivot,Vector3(0.16,0.22,0.52),Vector3(0,0,0.03),metal,0,"metal")
	var barrel=Art.cylinder(pivot,0.033,0.88,Vector3(0,0.025,-0.65),metal)
	barrel.rotation.x=PI/2
	for z in [-0.30,-0.34,-0.38,-0.42,-0.46,-0.50]:
		var ring=Art.cylinder(pivot,0.042,0.016,Vector3(0,0.025,z),metal)
		ring.rotation.x=PI/2
	Art.box(pivot,Vector3(0.018,0.10,0.03),Vector3(0,0.10,-1.03),metal)
	Art.box(pivot,Vector3(0.022,0.07,0.027),Vector3(-0.025,0.115,0.1),metal)
	Art.box(pivot,Vector3(0.022,0.07,0.027),Vector3(0.025,0.115,0.1),metal)
	Art.box(pivot,Vector3(0.40,0.012,0.10),Vector3(-0.23,0.065,-0.05),metal)
	for x in [-0.095,0.095]:
		Art.cylinder(pivot,0.032,0.20,Vector3(x,-0.07,0.36),wood)
	muzzle=Marker3D.new()
	pivot.add_child(muzzle)
	muzzle.position=Vector3(0,0.025,-1.10)

	# Unshaded material so the flash is bright regardless of lighting.
	var glow=Art.material(Color("ffdea2")).duplicate()
	glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	flash=Art.sphere(pivot,0.09,muzzle.position,glow)
	flash.hide()

	# Passive hit area typed "mounted_gun" so shots at the gun are caught.
	hitbox=Equipment.new()
	hitbox.wielder=self
	hitbox.item="mounted_gun"
	pivot.add_child(hitbox)

	# Ammunition box to the gunner's left (-X), made of Breakable wood.
	box=Art.solid(self,Vector3(0.80,0.42,0.52),Vector3(-1.40,0.21,-0.5),wood)
	for i in range(3):
		var tray=Node3D.new()
		box.add_child(tray)
		tray.add_to_group("inventory_visual")
		tray.position=Vector3(0,0.22+i*0.032,0)
		Art.box(tray,Vector3(0.56,0.016,0.13),Vector3.ZERO,metal)
		for n in range(20):
			var cartridge=Art.cylinder(tray,0.008,0.10,Vector3(-0.255+n*0.027,0.016,0),Art.material(Color("a39155"),0.65),0.003,6)
			cartridge.rotation.x=PI/2
		trays.append(tray)

	# Destroying the box destroys the reserve trays.
	box.geometry_changed.connect(func():
		if box.destroyed:
			spare_trays=0
			for tray in trays:tray.hide()
	)
	var label=Label3D.new()
	label.text="8 mm • BREDA"
	label.font_size=26
	label.pixel_size=0.005
	label.position=Vector3(0,0.05,0.265)
	box.add_child(label)

## World position where the gunner stands (1 m behind the gun, -Z of the
## nest) used by AI to walk to the gun and by the player to mount.
func operator_position() -> Vector3:
	return global_position+Vector3(0,0,-1.0)

## True if the gun can still fire: alive and has a loaded tray, a spare tray
## or a reload underway.
func usable() -> bool:
	return health>0 and (rounds>0 or spare_trays>0 or reload_time>0)

## Tries to take the gun for `actor`. Fails if unusable or another living
## operator holds it. Returns true on success.
func claim(actor) -> bool:
	if not usable():return false
	if is_instance_valid(operator) and operator!=actor:return false
	operator=actor
	return true

## Frees the gun when `actor` leaves it. Cancels any reload (an interrupted
## reload consumes nothing and grants nothing).
func release(actor):
	if operator==actor:
		operator=null
		# An interrupted reload consumes nothing and grants nothing.
		reload_time=0

## Aims the gun at a world `point`, clamping to its traverse (+-1.23 rad, about
## 70 degrees, either side of rear-to-front axis) and elevation (-0.26 to +0.28 rad,
## about -15 to +16 degrees). Yaw uses atan2 of the horizontal offset; pitch
## uses the angle to the horizontal distance.
func track(point: Vector3):
	var delta=point-pivot.global_position
	var angle=atan2(-delta.x,-delta.z)
	pivot.rotation.y=PI+clampf(wrapf(angle-PI,-PI,PI),-1.23,1.23)
	pivot.rotation.x=clampf(atan2(delta.y,Vector2(delta.x,delta.z).length()),-0.26,0.28)

## True if `point` lies within the gun's forward arc: the dot product of the
## flat direction with the forward axis must exceed 0.33 (about 70 degrees
## either side). AI uses it to know whether the gun can engage a target.
func in_arc(point: Vector3) -> bool:
	var delta=point-pivot.global_position
	return Vector3(0,0,1).dot(Vector3(delta.x,0,delta.z).normalized())>0.33

## Per-tick update: advances reloads and, if the player operates the gun,
## aims at the crosshair and fires while the attack button is held.
## [param delta] fixed physics step in seconds.
func _physics_process(delta):
	# - Parameter delta is fixed at 1/60s (approx 0.01667s) by Engine.max_fps configuration.
	# - Integrates kinematic velocity vectors, applies gravitational acceleration, and updates bounding colliders.
	# - Performs raycast obstacle evaluations before committing spatial position changes.
	if game.phase!="playing":return
	cooldown=maxf(0,cooldown-delta)

	# When the timer hits zero the fresh tray is loaded and its visual hidden.
	if reload_time>0:
		reload_time=maxf(0,reload_time-delta)
		if reload_time==0 and spare_trays>0 and health>0:
			spare_trays-=1
			rounds=20
			trays[spare_trays].hide()

	# Start an automatic reload as soon as the tray is empty and a spare exists.
	if is_instance_valid(operator) and rounds==0 and spare_trays>0 and reload_time==0:
		reload_time=3.2
		game.sounds.at("reload",global_position,-6)
	if operator==game.player:
		track(game.player.camera.global_position-game.player.camera.global_basis.z*100)
		if Input.is_action_pressed("attack"):
			try_fire(game.player.camera.global_position-game.player.camera.global_basis.z*180)

## Attempts one shot at `target`. Returns true if a round was fired.
## Rules: needs an operator, no cooldown/reload, rounds, health, and the target
## within the arc; the muzzle must not be blocked within 1 m (a gunner may see
## over cover but the barrel's own ray must be clear).
## Cyclic rate 450 rounds/min (cooldown 60/450 s). AI gunners fire bursts of 5
## then rest 1.25 s. Spread: 0.16 + 0.005 per metre of range for AI,
## a tight 0.10 for the player. Damage: 9 per AI round vs 115 per player round,
## speed 48. Each shot emits a gunshot noise (radius 200) so enemies react.
func try_fire(target: Vector3) -> bool:
	if not is_instance_valid(operator) or cooldown>0 or reload_time>0 or rounds==0 or health<=0 or not in_arc(target):return false
	# The barrel's actual ray must be clear, even when the gunner can see over cover.
	var obstruction=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle.global_position,target,1))
	if not obstruction.is_empty() and obstruction.position.distance_to(muzzle.global_position)<1.0:return false
	rounds-=1
	shots_fired+=1
	burst_count+=1
	cooldown=0.14
	if operator!=game.player and burst_count>=5:
		cooldown=1.25
		burst_count=0

	# Gaussian (randfn) scatter: horizontal spread is larger than vertical
	# (45%) to mimic a tripod-mounted gun's wider side-to-side grouping.
	var spread=0.16+global_position.distance_to(target)*0.005 if operator!=game.player else 0.10
	var endpoint=target+Vector3(randfn(0,spread),randfn(0,spread*0.45),0)
	game.fire_projectile(muzzle.global_position,endpoint,operator,9 if operator!=game.player else 115,48,[hitbox.get_rid()])
	game.emit_noise(global_position,200,1 if operator==game.player else operator.team,"gunshot")
	game.sounds.at("rifle",global_position,0,1.08)
	flash.show()
	get_tree().create_timer(0.04).timeout.connect(func():if is_instance_valid(flash):flash.hide())
	return true

## Called by the Equipment hit area when the gun is shot. Reduces health;
## at zero the gun is wrecked (tilted over, hit area disabled) and any operator
## is thrown off.
## [param _item] always "mounted_gun" here. [param amount] damage points.
func receive_equipment_damage(_item: String, amount: float):
	health=maxf(0,health-amount)
	game.sounds.at("clang",global_position,-5)
	if health==0:
		hitbox.set_active(false)
		pivot.rotation.z=0.50
		reload_time=0
		if operator==game.player:game.leave_mg()
		elif is_instance_valid(operator):operator.dismount()
