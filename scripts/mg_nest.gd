extends Node3D

# Breda modello 37: 8 mm ammunition in 20-round rigid feed trays.
# The adjacent box is the sole reserve supply: three full trays, never refilled.
const Art=preload("res://scripts/art.gd")
const Equipment=preload("res://scripts/equipment_hitbox.gd")
var game
var rounds: int=20
var spare_trays: int=3
var shots_fired: int=0
var health: float=260
var operator
var pivot: Node3D
var box
var trays: Array=[]
var hitbox
var cooldown: float=0
var reload_time: float=0
var burst_count: int=0
var muzzle: Marker3D
var flash: MeshInstance3D

func _ready():
	var metal=Art.material(Color("404742"),0.72,0.43)
	var wood=Art.material(Color("635c43"))
	# Low tripod behind a U-shaped sandbag emplacement, open at the rear.
	for p in [Vector3(-0.7,0,0.4),Vector3(0.7,0,0.4),Vector3(0,0,-1)]:
		var leg=Art.solid(self,Vector3(0.085,0.9,0.085),p*0.5+Vector3(0,0.42,0),metal,0,"metal")
		leg.quaternion=Quaternion(Vector3.UP,(Vector3(0,0.9,0)-p).normalized())
	pivot=Node3D.new()
	add_child(pivot)
	pivot.position.y=1.15
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
	var glow=Art.material(Color("ffdea2")).duplicate()
	glow.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	flash=Art.sphere(pivot,0.09,muzzle.position,glow)
	flash.hide()
	hitbox=Equipment.new()
	hitbox.wielder=self
	hitbox.item="mounted_gun"
	pivot.add_child(hitbox)
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

func operator_position() -> Vector3:
	return global_position+Vector3(0,0,-1.0)

func usable() -> bool:
	return health>0 and (rounds>0 or spare_trays>0 or reload_time>0)

func claim(actor) -> bool:
	if not usable():return false
	if is_instance_valid(operator) and operator!=actor:return false
	operator=actor
	return true

func release(actor):
	if operator==actor:
		operator=null
		# An interrupted reload consumes nothing and grants nothing.
		reload_time=0

func track(point: Vector3):
	var delta=point-pivot.global_position
	var angle=atan2(-delta.x,-delta.z)
	pivot.rotation.y=PI+clampf(wrapf(angle-PI,-PI,PI),-1.23,1.23)
	pivot.rotation.x=clampf(atan2(delta.y,Vector2(delta.x,delta.z).length()),-0.26,0.28)

func in_arc(point: Vector3) -> bool:
	var delta=point-pivot.global_position
	return Vector3(0,0,1).dot(Vector3(delta.x,0,delta.z).normalized())>0.33

func _physics_process(delta):
	if game.phase!="playing":return
	cooldown=maxf(-delta,cooldown-delta)
	if reload_time>0:
		reload_time=maxf(0,reload_time-delta)
		if reload_time==0 and spare_trays>0 and health>0:
			spare_trays-=1
			rounds=20
			trays[spare_trays].hide()
	if is_instance_valid(operator) and rounds==0 and spare_trays>0 and reload_time==0:
		reload_time=3.2
		game.sounds.at("reload",global_position,-6)
	if operator==game.player:
		track(game.player.camera.global_position-game.player.camera.global_basis.z*100)
		if Input.is_action_pressed("attack"):
			try_fire(game.player.camera.global_position-game.player.camera.global_basis.z*180)

func try_fire(target: Vector3) -> bool:
	if not is_instance_valid(operator) or cooldown>0.000001 or reload_time>0 or rounds==0 or health<=0 or not in_arc(target):return false
	# The barrel's actual ray must be clear, even when the gunner can see over cover.
	var obstruction=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(muzzle.global_position,target,1))
	if not obstruction.is_empty() and obstruction.position.distance_to(muzzle.global_position)<1.0:return false
	rounds-=1
	shots_fired+=1
	burst_count+=1
	cooldown+=60.0/450.0
	if operator!=game.player and burst_count>=5:
		cooldown=1.25
		burst_count=0
	var spread=0.16+global_position.distance_to(target)*0.005 if operator!=game.player else 0.10
	var endpoint=target+Vector3(randfn(0,spread),randfn(0,spread*0.45),0)
	game.fire_projectile(muzzle.global_position,endpoint,operator,9 if operator!=game.player else 115,48,[hitbox.get_rid()])
	game.emit_noise(global_position,200,1 if operator==game.player else operator.team,"gunshot")
	game.sounds.at("rifle",global_position,0,1.08)
	flash.show()
	get_tree().create_timer(0.04).timeout.connect(func():if is_instance_valid(flash):flash.hide())
	return true

func receive_equipment_damage(_item: String, amount: float):
	health=maxf(0,health-amount)
	game.sounds.at("clang",global_position,-5)
	if health==0:
		hitbox.set_active(false)
		pivot.rotation.z=0.50
		reload_time=0
		if operator==game.player:game.leave_mg()
		elif is_instance_valid(operator):operator.dismount()
