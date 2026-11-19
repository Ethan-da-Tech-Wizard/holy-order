# ==============================================================================
# Program: mg_nest.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for mg_nest.gd.
# ==============================================================================
## Fixed Breda 37 machine-gun emplacement (desert mission).
##
## Builds a tripod gun with an ammunition box beside it. One soldier (the AI or the
## player) claims it as `operator`; the gun then tracks a target within a limited
## arc, fires bursts, and reloads from three spare trays. Damage to the gun itself comes
## through the attached equipment hitbox (`receive_equipment_damage`). `game` must be set by
## the mission before _ready.
extends Node3D

# Breda modello 37: 8 mm ammunition in 20-round rigid feed trays.
# The adjacent box is the sole reserve supply: three full trays, never refilled.
# Art helper and the equipment hitbox script (so bullets can disable the gun).
# Breda modello 37: 8 mm ammunition in 20-round rigid feed trays.
# The adjacent box is the sole reserve supply: three full trays, never refilled.
const Art=preload("res://scripts/art.gd")
const Equipment=preload("res://scripts/equipment_hitbox.gd")

# Mission controller (fire_projectile, emit_noise, sounds, player, phase).
var game

# Rounds in the current tray.
var rounds: int=20

# Full trays left in the ammo box.
var spare_trays: int=3

# Statistics for tests and the debug report.
var shots_fired: int=0

# Gun health; 260 points of damage knocks it out.
var health: float=260

# Soldier currently manning the gun, or null.
var operator

# Rotating part (gun body and barrel) that tracks targets.
var pivot: Node3D

# Ammo box node; shooting it to pieces destroys the spare trays.
var box

# Visible tray models in the box, one per spare tray.
var trays: Array=[]

# The equipment hitbox attached to the gun.
var hitbox

# Seconds until the next shot may fire; reload_time is the time left in a reload.
var cooldown: float=0
var reload_time: float=0

# Shots in the current burst; AI gunners pause after 5.
var burst_count: int=0

# Where bullets come from and the muzzle flash mesh.
var muzzle: Marker3D
var flash: MeshInstance3D

## Build the tripod, gun, hitbox, ammo box with three trays and the label.
func _ready():
	var metal=Art.material(Color("404742"),0.72,0.43)
	var wood=Art.material(Color("635c43"))
	# Low tripod behind a U-shaped sandbag emplacement, open at the rear.
	# Low tripod behind a U-shaped sandbag emplacement, open at the rear.
	for p in [Vector3(-0.7,0,0.4),Vector3(0.7,0,0.4),Vector3(0,0,-1)]:
		var leg=Art.solid(self,Vector3(0.085,0.9,0.085),p*0.5+Vector3(0,0.42,0),metal,0,"metal")
		leg.quaternion=Quaternion(Vector3.UP,(Vector3(0,0.9,0)-p).normalized())
	# The pivot (gun body) is a separate node so aiming rotates only the gun, not the tripod. It faces +z at rest (rotation y = PI).
	pivot=Node3D.new()
	add_child(pivot)
	pivot.position.y=1.15
	pivot.rotation.y=PI
	Art.solid(pivot,Vector3(0.16,0.22,0.52),Vector3(0,0,0.03),metal,0,"metal")
	# Barrel and cooling rings.
	var barrel=Art.cylinder(pivot,0.033,0.88,Vector3(0,0.025,-0.65),metal)
	barrel.rotation.x=PI/2
	for z in [-0.30,-0.34,-0.38,-0.42,-0.46,-0.50]:
		var ring=Art.cylinder(pivot,0.042,0.016,Vector3(0,0.025,z),metal)
		ring.rotation.x=PI/2
	# Front sight, rear sight and tray guide.
	Art.box(pivot,Vector3(0.018,0.10,0.03),Vector3(0,0.10,-1.03),metal)
	Art.box(pivot,Vector3(0.022,0.07,0.027),Vector3(-0.025,0.115,0.1),metal)
	Art.box(pivot,Vector3(0.022,0.07,0.027),Vector3(0.025,0.115,0.1),metal)
	Art.box(pivot,Vector3(0.40,0.012,0.10),Vector3(-0.23,0.065,-0.05),metal)
	for x in [-0.095,0.095]:
		Art.cylinder(pivot,0.032,0.20,Vector3(x,-0.07,0.36),wood)
	# Muzzle marker is where projectiles start.
	muzzle=Marker3D.new()
	pivot.add_child(muzzle)
	muzzle.position=Vector3(0,0.025,-1.10)
	# Muzzle flash uses an unshaded material so it glows; it is shown for 0.04 s per shot.
	var glow=Art.material(Color("ffdea2")).duplicate()
	glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	flash=Art.sphere(pivot,0.09,muzzle.position,glow)
	flash.hide()
	# The hitbox lets bullets hit the gun itself and forwards damage to receive_equipment_damage().
	hitbox=Equipment.new()
	hitbox.wielder=self
	hitbox.item="mounted_gun"
	pivot.add_child(hitbox)
	# Ammo box with three trays of 20 cartridges each.
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
	# Destroying the box also destroys the reserve ammunition.
	box.geometry_changed.connect(func():
		if box.destroyed:
			spare_trays=0
			for tray in trays:tray.hide()
	)
	# A small label on the box side.
	var label=Label3D.new()
	label.text="8 mm • BREDA"
	label.font_size=26
	label.pixel_size=0.005
	label.position=Vector3(0,0.05,0.265)
	box.add_child(label)

## Where a gunner should stand to operate the gun.
func operator_position() -> Vector3:
	return global_position+Vector3(0,0,-1.0)

## Whether the gun is still worth operating.
func usable() -> bool:
	return health>0 and (rounds>0 or spare_trays>0 or reload_time>0)

## Reserve the gun for an operator.
## @return true on success; false when the gun is broken or someone else already uses it.
func claim(actor) -> bool:
	if not usable():return false
	if is_instance_valid(operator) and operator!=actor:return false
	operator=actor
	return true

## Release the gun (the operator died, left or was replaced).
func release(actor):
	if operator==actor:
		operator=null
		# An interrupted reload consumes nothing and grants nothing.
		# An interrupted reload consumes nothing and grants nothing.
		reload_time=0

## Rotate the gun toward a world point, within its traverse limits.
## @param point World position to aim at.
func track(point: Vector3):
	var delta=point-pivot.global_position
	# Yaw about the up axis; the gun faces +z at rest so offsets are measured from PI.
	var angle=atan2(-delta.x,-delta.z)
	# Traverse limited to about +/-70 degrees (1.23 rad) and elevation to about -15 / +16 degrees.
	pivot.rotation.y=PI+clampf(wrapf(angle-PI,-PI,PI),-1.23,1.23)
	pivot.rotation.x=clampf(atan2(delta.y,Vector2(delta.x,delta.z).length()),-0.26,0.28)

## Whether a target is in front of the gun (within about 70 degrees of the forward direction).
func in_arc(point: Vector3) -> bool:
	var delta=point-pivot.global_position
	# Dot product greater than 0.33 means within roughly 70 degrees of the forward axis (+z).
	return Vector3(0,0,1).dot(Vector3(delta.x,0,delta.z).normalized())>0.33

## Update cooldowns and reload, and let the player fire when manning the gun.
func _physics_process(delta):
	# Only during the playing phase.
	if game.phase!="playing":return
	# The negative floor lets leftover time carry into the next shot so the fire rate stays exact.
	cooldown=maxf(-delta,cooldown-delta)
	if reload_time>0:
		reload_time=maxf(0,reload_time-delta)
		# When the reload timer ends, load a fresh tray and hide its model.
		if reload_time==0 and spare_trays>0 and health>0:
			spare_trays-=1
			rounds=20
			trays[spare_trays].hide()
	# Start a 3.2 s reload when the tray is empty and spare trays remain.
	if is_instance_valid(operator) and rounds==0 and spare_trays>0 and reload_time==0:
		reload_time=3.2
		game.sounds.at("reload",global_position,-6)
	# The player's gun follows the camera direction and fires while the attack button is held.
	if operator==game.player:
		track(game.player.camera.global_position-game.player.camera.global_basis.z*100)
		if Input.is_action_pressed("attack"):
			try_fire(game.player.camera.global_position-game.player.camera.global_basis.z*180)

## Fire one round at a target if allowed.
## @param target World position to shoot at.
## @return true if a shot was fired.
func try_fire(target: Vector3) -> bool:
	if not is_instance_valid(operator) or cooldown>0.000001 or reload_time>0 or rounds==0 or health<=0 or not in_arc(target):return false
	# The barrel's actual ray must be clear, even when the gunner can see over cover.
	# The barrel's actual ray must be clear, even when the gunner can see over cover.
	var obstruction=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle.global_position,target,1))
	if not obstruction.is_empty() and obstruction.position.distance_to(muzzle.global_position)<1.0:return false
	rounds-=1
	shots_fired+=1
	burst_count+=1
	# 450 rounds per minute.
	cooldown+=60.0/450.0
	# AI gunners fire 5-round bursts then pause 1.25 s.
	if operator!=game.player and burst_count>=5:
		cooldown=1.25
		burst_count=0
	# Spread (metres at the target): AI gets wider with distance; the player has a tight fixed spread.
	var spread=0.16+global_position.distance_to(target)*0.005 if operator!=game.player else 0.10
	var endpoint=target+Vector3(randfn(0,spread),randfn(0,spread*0.45),0)
	# Parameters: start, end, shooter, damage (9 for AI, 115 for the player), speed 48, nodes to ignore (the gun's own hitbox).
	game.fire_projectile(muzzle.global_position,endpoint,operator,9 if operator!=game.player else 115,48,[hitbox.get_rid()])
	# Gunshot noise radius 200 m, attributed to the shooter's team, so enemies nearby react.
	game.emit_noise(global_position,200,1 if operator==game.player else operator.team,"gunshot")
	game.sounds.at("rifle",global_position,0,1.08)
	flash.show()
	# Hide the muzzle flash shortly after.
	get_tree().create_timer(0.04).timeout.connect(func():if is_instance_valid(flash):flash.hide())
	return true

## Damage the gun (from hits on its hitbox).
## @param _item Item name (unused).
## @param amount Damage points.
func receive_equipment_damage(_item: String, amount: float):
	health=maxf(0,health-amount)
	game.sounds.at("clang",global_position,-5)
	# At zero health the gun is wrecked: the barrel droops, the hitbox is disabled and the operator is thrown off.
	if health==0:
		hitbox.set_active(false)
		pivot.rotation.z=0.50
		reload_time=0
		if operator==game.player:game.leave_mg()
		elif is_instance_valid(operator):operator.dismount()
