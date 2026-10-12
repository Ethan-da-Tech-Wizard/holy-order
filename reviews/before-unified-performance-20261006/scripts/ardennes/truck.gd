extends Node3D

const Art=preload("res://scripts/art.gd")
const ArmoredPanel=preload("res://scripts/ardennes/armored_panel.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")
const STUCK_SECONDS=6.0
const MIN_PROGRESS=3.05 # about ten feet, measured over the window above
const END_PROGRESS=665.0
var game
var index:int=0
var progress:float=0
var speed:float=0
var health:float=4500
var destroyed:bool=false
var stopped:bool=false
var disabled:bool=false
var unloaded:bool=false
var arrived:bool=false
var dismount_reason:String=""
var lane_offset:float=0
var desired_lane:float=0
var pass_until:float=-1
var bypass_attempts:int=0
var blocked_by=-1
var travel_window:float=0
var window_origin:Vector3
var occupants:Array=[]
var parts:Array=[]
var wheels:Array=[]
var wheel_health:Array[float]=[600,600,600,600,600,600]
var engine_loop:AudioStreamPlayer3D
var total_damage:float=0
var bullet_hits:int=0
var last_hit_time:float=-100
var target_bias:Vector3=Vector3(0,1.8,0.7)
var last_transform_progress:float=-100
var last_transform_lane:float=-100

func _ready():
	var olive=Art.material(Color("535c43"),0.18,0.83)
	var wood=Art.material(Color("655d46"))
	var steel=Art.material(Color("333b38"),0.68,0.61)
	var rubber=Art.material(Color("202423"))
	part(Vector3(2.15,0.28,6.2),Vector3(0,0.85,0),steel,"metal","chassis")
	part(Vector3(2.2,0.18,3.9),Vector3(0,1.31,0.91),olive,"metal","floor")
	part(Vector3(1.7,0.68,1.50),Vector3(0,1.43,-2.25),olive,"metal","engine")
	part(Vector3(2.2,0.6,1.35),Vector3(0,1.35,-1.35),olive,"metal","cab")
	part(Vector3(2.17,0.14,1.35),Vector3(0,2.52,-1.39),olive,"metal","cab")
	for x in [-1.07,1.07]:
		part(Vector3(0.07,0.92,1.30),Vector3(x,1.86,-1.34),olive,"metal","cab")
		part(Vector3(0.16,0.82,3.87),Vector3(x,1.85,0.97),olive,"metal","armor")
		part(Vector3(0.34,0.13,3.50),Vector3(x*0.79,1.68,1),wood,"wood","bench")
		# Steel troop compartment, including roof and a narrow rear viewing slit.
		part(Vector3(0.14,1.10,3.90),Vector3(x,2.71,0.98),olive,"metal","armor")
		for z in [-0.86,0.38,1.65,2.90]:
			part(Vector3(0.045,1.64,0.045),Vector3(x,2.4,z),olive,"metal","hoop")
		for z in [-2.25,1.08,2.25]:
			var wheel=part(Vector3(0.34,1.1,1.1),Vector3(x*1.11,0.62,z),rubber,"metal","wheel")
			wheel.set_meta("wheel_index",wheels.size())
			for mesh in wheel.owned_meshes():mesh.queue_free()
			var tire=Art.cylinder(wheel,0.56,0.34,Vector3.ZERO,rubber,-1,12)
			tire.rotation.z=PI/2
			var disk=Art.cylinder(wheel,0.27,0.36,Vector3.ZERO,olive,-1,10)
			disk.rotation.z=PI/2
			wheels.append(wheel)
	part(Vector3(2.2,0.14,3.98),Vector3(0,3.28,0.96),olive,"metal","armor")
	part(Vector3(2.12,1.10,0.14),Vector3(0,2.71,-0.98),olive,"metal","armor")
	part(Vector3(2.17,0.78,0.14),Vector3(0,1.81,2.91),olive,"metal","tailgate")
	for side in [-1,1]:part(Vector3(0.64,1.08,0.14),Vector3(side*0.765,2.73,2.97),olive,"metal","armor")
	part(Vector3(0.90,0.60,0.14),Vector3(0,2.50,2.97),olive,"metal","armor")
	part(Vector3(0.90,0.20,0.14),Vector3(0,3.18,2.97),olive,"metal","armor")
	for x in [-0.88,0.88]:
		Art.box(self,Vector3(0.20,0.20,0.055),Vector3(x,1.63,-3.05),Art.material(Color("dbd1a9")))
	# Cab crew are visual vehicle crew; the combat passengers have individual health.
	for x in [-0.51,0.51]:
		var driver=Kit.soldier(self,1,index)
		driver.root.position=Vector3(x,0.40,-1.32)
		for leg in driver.legs:leg.hide()
	update_transform()
	window_origin=position

func part(size:Vector3,offset:Vector3,mat:Material,kind:String,role:String):
	var body=ArmoredPanel.new()
	body.material_kind=kind
	body.battle_world=game.world
	body.position=offset
	add_child(body)
	Art.box(body,size,Vector3.ZERO,mat)
	var shape=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=size
	shape.shape=box
	body.add_child(shape)
	body.truck_owner=self
	body.set_meta("truck_role",role)
	parts.append(body)
	return body

func seat_transform(seat:int)->Transform3D:
	var side=-1 if seat%2==0 else 1
	var offset=Vector3(side*0.70,1.32,-0.45+float(seat/2)*0.60)
	return global_transform*Transform3D(Basis(Vector3.UP,-side*PI/2),offset)

func gunner_transform()->Transform3D:
	return seat_transform(1)

func has_passengers()->bool:
	if unloaded:return false
	if game.player.truck==self and game.player.health>0:return true
	for actor in occupants:
		if actor.alive and actor.truck==self:return true
	return false

func target_point(shooter)->Vector3:
	# Finite bursts move between targets and panels; wheel hits are real ray hits.
	var choice=(shooter.index+int(game.elapsed/2.2))%10
	if choice==0:
		var wheel=wheels[(shooter.index+int(game.elapsed))%wheels.size()]
		return wheel.global_position
	var side=signf(to_local(shooter.global_position).x)
	if choice<3:return to_global(Vector3(side*0.9,1.75,-2.0))
	return to_global(Vector3(side*1.08,2.15,0.25+float(choice%4)*0.62))

func update_transform():
	if is_equal_approx(progress,last_transform_progress) and is_equal_approx(lane_offset,last_transform_lane):return
	last_transform_progress=progress
	last_transform_lane=lane_offset
	position=game.world.road_point(progress)
	var ahead=game.world.road_point(progress+1)
	var heading=(ahead-position).normalized()
	var right=heading.cross(Vector3.UP).normalized()
	position+=right*lane_offset
	position.y=game.world.surface_height(position.x,position.z)
	rotation.y=atan2(-heading.x,-heading.z)
	rotation.x=-asin(clampf(heading.y,-0.16,0.16))

func can_pass(lane:float)->bool:
	for other in game.trucks:
		if other==self:continue
		if absf(other.progress-progress)<11 and absf(other.lane_offset-lane)<2.7:return false
	var at=game.world.road_point(progress+8)
	at.x+=lane
	return absf(game.world.surface_height(at.x,at.z)-game.world.road_point(progress+8).y)<1.0

func tick(delta:float,_front=null):
	if destroyed or unloaded:return
	if not has_passengers():
		dismount("crew lost")
		return
	var target_speed=8.2
	var flats=wheel_health.filter(func(h):return h<=0).size()
	disabled=flats>=2 or health<=0
	if flats==1:target_speed*=0.68
	if disabled or arrived:target_speed=0
	var obstruction=null
	var gap=INF
	for other in game.trucks:
		if other==self:continue
		var ahead=other.progress-progress
		if ahead>0 and ahead<18 and absf(other.lane_offset-lane_offset)<2.7 and ahead<gap:
			obstruction=other
			gap=ahead
	if obstruction!=null:
		if obstruction.speed<2 or obstruction.disabled or obstruction.destroyed or obstruction.unloaded:
			if blocked_by!=obstruction.index:
				blocked_by=obstruction.index
				bypass_attempts+=1
			for lane in [-3.5,3.5]:
				if can_pass(lane):
					desired_lane=lane
					pass_until=obstruction.progress+11
					break
		if gap<10 and absf(lane_offset-obstruction.lane_offset)<2.7:target_speed=0
		elif gap<15:target_speed=minf(target_speed,maxf(1,obstruction.speed))
	elif progress>pass_until and desired_lane!=0 and can_pass(0):desired_lane=0
	lane_offset=move_toward(lane_offset,desired_lane,delta*1.9)
	speed=move_toward(speed,target_speed,delta*(4.0 if target_speed<speed else 2.2))
	if not disabled:
		progress=minf(END_PROGRESS,progress+speed*delta)
		update_transform()
	if progress>=END_PROGRESS-0.05:
		arrived=true
		stopped=true
		speed=0
	for wheel in wheels:
		for mesh in wheel.get_children():
			if mesh is MeshInstance3D:mesh.rotate_y(speed*delta/0.56)
	travel_window+=delta
	if travel_window>=STUCK_SECONDS:
		var moved=position.distance_to(window_origin)
		travel_window=0
		window_origin=position
		if moved<MIN_PROGRESS:
			dismount("arrival" if arrived else ("wheels disabled" if disabled else "stuck"))

func receive_part_damage(amount:float,point:Vector3,explosive:bool,part_node=null):
	if destroyed:return
	total_damage+=amount
	last_hit_time=game.elapsed
	if not explosive:bullet_hits+=1
	if part_node!=null and part_node.has_meta("wheel_index"):
		var wheel_index=int(part_node.get_meta("wheel_index"))
		wheel_health[wheel_index]=maxf(0,wheel_health[wheel_index]-amount*(0.32 if explosive else 0.08))
		if wheel_health[wheel_index]==0:
			for mesh in wheels[wheel_index].get_children():
				if mesh is MeshInstance3D:mesh.scale=Vector3(1,0.60,1)
		disabled=wheel_health.filter(func(h):return h<=0).size()>=2
		return
	var role=part_node.get_meta("truck_role","") if part_node!=null else ""
	var harm=amount*(0.012 if role=="engine" else 0.001)
	if explosive:harm=amount*0.18
	health=maxf(0,health-harm)
	if health<=0:wreck(false)

func passenger_damage(amount:float,kind:String)->float:
	if destroyed:return amount
	return amount*(0.12 if kind=="rifle" else (0.22 if kind=="explosion" else 1.0))

func receive_ambush_strike(point:Vector3):
	# A rocket can stop the convoy without a scripted execution of everyone aboard.
	receive_part_damage(1400,point,true)
	if destroyed:return
	disabled=true
	dismount("armored ambush stop")

func wreck(scripted:bool):
	if destroyed:return
	destroyed=true
	disabled=true
	health=0
	speed=0
	stopped=true
	rotation.z=randf_range(-0.10,0.10)
	game.vehicle_wrecked(self,scripted)
	var scorch=Art.material(Color("292a25"),0.3,0.92)
	for item in parts:
		for mesh in item.owned_meshes():mesh.material_override=scorch
	game.add_wreck_fire(global_position+Vector3(0,1.7,-1.9))
	for actor in occupants.duplicate():
		if actor.alive and actor.truck==self:
			actor.take_damage(randf_range(24,48),global_position,"explosion")
			if actor.alive:actor.dismount()
	if game.player.truck==self:
		game.player.take_damage(45,position,"explosion")
		if game.player.health>0:game.player.dismount()
	game.truck_dismounted(self)
	game.world.obstacles.append({"p":global_position,"r":3.4,"node":parts[0]})
	game.world.geometry_updated(global_position)
	unloaded=true

func dismount(reason:String="orders"):
	if unloaded:return
	unloaded=true
	stopped=true
	speed=0
	dismount_reason=reason
	for actor in occupants:
		if actor.alive and actor.truck==self:actor.dismount()
	if game.player.truck==self:game.player.dismount()
	game.truck_dismounted(self)
