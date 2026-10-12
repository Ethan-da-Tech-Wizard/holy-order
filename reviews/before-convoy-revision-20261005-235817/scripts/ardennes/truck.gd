extends Node3D

const Art=preload("res://scripts/art.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")
var game
var index:int=0
var progress:float=0
var speed:float=0
var health:float=900
var destroyed:bool=false
var stopped:bool=false
var occupants:Array=[]
var parts:Array=[]
var wheels:Array=[]
var ring_gunner
var engine_loop:AudioStreamPlayer3D
var total_damage:float=0

func _ready():
	var olive=Art.material(Color("535c43"),0.18,0.83)
	var wood=Art.material(Color("655d46"))
	var steel=Art.material(Color("333b38"),0.68,0.61)
	var rubber=Art.material(Color("202423"))
	part(Vector3(2.15,0.28,6.2),Vector3(0,0.85,0),steel,"metal")
	part(Vector3(2.2,0.16,3.9),Vector3(0,1.31,0.91),wood,"wood")
	part(Vector3(1.7,0.68,1.50),Vector3(0,1.43,-2.25),olive,"metal")
	part(Vector3(2.2,0.6,1.35),Vector3(0,1.35,-1.35),olive,"metal")
	part(Vector3(2.17,0.14,1.35),Vector3(0,2.52,-1.39),olive,"metal")
	for x in [-1.07,1.07]:
		part(Vector3(0.07,0.92,1.30),Vector3(x,1.86,-1.34),olive,"metal")
		part(Vector3(0.11,0.79,3.87),Vector3(x,1.82,0.97),wood,"wood")
		part(Vector3(0.34,0.13,3.50),Vector3(x*0.79,1.68,1),wood,"wood")
		for z in [-2.25,1.08,2.25]:
			var hub=Node3D.new()
			add_child(hub)
			hub.position=Vector3(x*1.11,0.62,z)
			var tire=Art.cylinder(hub,0.56,0.34,Vector3.ZERO,rubber,-1,16)
			tire.rotation.z=PI/2
			var disk=Art.cylinder(hub,0.27,0.37,Vector3.ZERO,olive,-1,12)
			disk.rotation.z=PI/2
			wheels.append(hub)
	part(Vector3(2.17,0.78,0.10),Vector3(0,1.81,2.91),wood,"wood")
	for x in [-0.88,0.88]:
		Art.box(self,Vector3(0.20,0.20,0.055),Vector3(x,1.63,-3.05),Art.material(Color("dbd1a9")))
	for x in [-1.0,0,1.0]:
		Art.segment(self,Vector3(x,1.95,-2.05),Vector3(x,2.47,-2.03),0.028,olive)
	Art.segment(self,Vector3(-1.0,2.47,-2.03),Vector3(1,2.47,-2.03),0.028,olive)
	# Cab crew are part of the vehicle model; the twelve combat passengers are actors.
	for x in [-0.51,0.51]:
		var driver=Kit.soldier(self,1,index)
		driver.root.position=Vector3(x,0.40,-1.32)
		for leg in driver.legs:leg.hide()
	var star=Label3D.new()
	star.text="★"
	star.font_size=64
	star.pixel_size=0.012
	star.position=Vector3(0,1.79,-2.26)
	star.rotation.x=-PI/2
	star.modulate=Color("d4d5ba")
	add_child(star)
	if index in [2,6]:
		var ring=TorusMesh.new()
		ring.inner_radius=0.48
		ring.outer_radius=0.54
		ring.rings=20
		ring.ring_segments=6
		Art.mesh(self,ring,Vector3(0,2.65,-1.25),steel)
		Art.segment(self,Vector3(0,2.63,-1.75),Vector3(0,3.04,-1.75),0.045,steel)
	update_transform()

func part(size:Vector3,offset:Vector3,mat:Material,kind:String):
	var body=game.world.solid(size,offset,mat,kind,self)
	body.truck_owner=self
	parts.append(body)
	return body

func seat_transform(seat:int)->Transform3D:
	var side=-1 if seat%2==0 else 1
	var offset=Vector3(side*0.69,1.32,-0.50+float(seat/2)*0.61)
	return global_transform*Transform3D(Basis(Vector3.UP,-side*PI/2),offset)

func gunner_transform()->Transform3D:
	return global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.40,-1.05))

func update_transform():
	position=game.world.road_point(progress)
	var ahead=game.world.road_point(progress+1.0)
	var heading=(ahead-position).normalized()
	rotation.y=atan2(-heading.x,-heading.z)
	rotation.x=asin(clampf(heading.y,-0.2,0.2))

func tick(delta:float,front):
	if destroyed or stopped or game.column_stopped:
		speed=move_toward(speed,0,delta*10)
	else:speed=move_toward(speed,7.5,delta*2)
	if front!=null and front.progress-progress<12:speed=minf(speed,maxf(0,front.speed-1.0))
	if not destroyed:
		progress+=speed*delta
		update_transform()
	for wheel in wheels:wheel.rotate_x(speed*delta/0.56)

func receive_part_damage(amount:float,point:Vector3,explosive:bool):
	if destroyed:return
	var local=to_local(point)
	var engine=local.z< -1.65
	var harm=amount*(0.48 if engine else 0.025)
	if explosive:harm=amount
	health=maxf(0,health-harm)
	total_damage+=harm
	if health<=0:wreck(false)

func wreck(scripted:bool):
	if destroyed:return
	destroyed=true
	health=0
	speed=0
	stopped=true
	rotation.z=randf_range(-0.10,0.10)
	game.vehicle_wrecked(self,scripted)
	for i in range(parts.size()):
		if i%3==1:parts[i].carve(parts[i].global_position,0.8)
	var scorch=Art.material(Color("292a25"),0.3,0.92)
	for item in parts:
		for mesh in item.owned_meshes():mesh.material_override=scorch
	game.add_wreck_fire(global_position+Vector3(0,1.7,-1.9))
	# All passengers were hittable during the drive. The wreck's blast also reaches them.
	for actor in occupants.duplicate():
		if actor.alive:actor.take_damage(randf_range(108,155),global_position,"explosion")
	game.world.obstacles.append({"p":global_position,"r":3.4,"node":parts[0]})
	game.world.geometry_updated(global_position)

func dismount():
	for actor in occupants:
		if actor.alive:
			actor.dismount()
	if game.player.truck==self:game.player.dismount()
