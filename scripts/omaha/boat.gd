extends Node3D
const Art=preload("res://scripts/art.gd")
const Armor=preload("res://scripts/omaha/armor.gd")
const APPROACH_SECONDS:float=32.0
const LAND_Z:float=20.0
const SECOND_WAVE_DELAY:float=120.0
var game
var index:int=0
var wave:int=0
var lane_x:float=0
var occupants:Array=[]
var crew:Array=[]
var parts:Array=[]
var ramp:Node3D
var stopped:bool=false
var unloaded:bool=false
var arrived:bool=false
var destroyed:bool=false
var disabled:bool=false
var landed_at:float=-1
var dismount_reason:String=""
var health:float=12000
var bullet_hits:int=0
var total_damage:float=0
var engine_loop=null
var wake:MeshInstance3D
var departure_at:float=-1
var departing:bool=false
var departed:bool=false
var passenger_pose_at:float=-1
const RETURN_LANE_OFFSET:float=6.0
const HOLD_Z:float=430.0
const APPROACH_Z:float=270.0
const EXIT_Z:float=330.0

func _ready():
	var paint=Art.material(Color("565f59"),0.65,0.64)
	var dark=Art.material(Color("222e2e"),0.40,0.65)
	part(Vector3(3.4,0.22,10.8),Vector3(0,0.13,0),paint,1800)
	for side in [-1,1]:
		for section in range(6):
			part(Vector3(0.10,1.55,1.78),Vector3(side*1.68,0.93,-4.48+section*1.78),paint,780)
		for z in [-4.9,-3.1,-1.3,0.5,2.3,4.1]:
			Art.box(self,Vector3(0.11,1.53,0.08),Vector3(side*1.59,0.92,z),dark)
	part(Vector3(3.4,1.48,0.13),Vector3(0,0.9,5.38),paint,1100)
	part(Vector3(2.3,0.82,1.85),Vector3(0,0.68,4.25),paint,1800)
	ramp=Node3D.new()
	add_child(ramp)
	ramp.position=Vector3(0,0.24,-5.42)
	part(Vector3(3.17,1.58,0.16),Vector3(0,0.79,0),paint,1100,ramp)
	for x in [-1.32,-0.66,0,0.66,1.32]:Art.box(ramp,Vector3(0.05,1.5,0.05),Vector3(x,0.80,0.11),dark)
	for side in [-1,1]:
		Art.cylinder(self,0.055,1.3,Vector3(side*1.12,1.45,3.35),dark,-1,8)
		var ring=TorusMesh.new()
		ring.inner_radius=0.39
		ring.outer_radius=0.43
		ring.rings=20
		ring.ring_segments=6
		Art.mesh(self,ring,Vector3(side*1.12,1.65,3.35),paint)
		var number=Label3D.new()
		number.text="PA 26–%02d"%(index+1)
		number.font_size=32
		number.pixel_size=0.008
		number.position=Vector3(side*1.742,1.00,0)
		number.rotation.y=side*PI/2
		number.modulate=Color("c1c5b6")
		add_child(number)
	# The coxswain stands behind a small reinforced shield, not an invisible god mode.
	part(Vector3(1.05,0.85,0.15),Vector3(0,1.47,3.77),paint,16000)
	Art.cylinder(self,0.12,0.06,Vector3(0,1.4,4.04),dark,-1,12).rotation.x=PI/2
	var foam=Art.material(Color("738c8d"),0,0.95)
	wake=Art.box(self,Vector3(3.2,0.015,12),Vector3(0,-0.26,11.2),foam)
	wake.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	update_course(0)
	preload("res://scripts/vehicle_visuals.gd").batch_boxes(self,[ramp,wake])

func part(size:Vector3,p:Vector3,mat:Material,strength:float,parent:Node3D=self):
	var body=Armor.new()
	body.material_kind="metal"
	body.truck_owner=self
	body.hull_panel=true
	body.integrity=strength
	body.max_integrity=strength
	parent.add_child(body)
	body.collision_layer|=128
	body.position=p
	Art.box(body,size,Vector3.ZERO,mat)
	var cs=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=size
	cs.shape=box
	body.add_child(cs)
	parts.append(body)
	return body

func seat_transform(seat:int)->Transform3D:
	var row=int(seat/3)
	var p=Vector3((seat%3-1)*0.80,0.27,-4.25+row*0.78)
	if landed_at>=0:
		var t=maxf(0,game.elapsed-landed_at-1.5-row*0.36)
		p.z=maxf(-6.95,p.z-t*2.55)
	return global_transform*Transform3D(Basis.IDENTITY,p)

func crew_transform(slot:int)->Transform3D:
	return global_transform*Transform3D(Basis.IDENTITY,Vector3(0 if slot==2 else (-1.12 if slot==0 else 1.12),0.38,4.4 if slot==2 else 3.35))

func update_course(now:float):
	if departing:
		var t=maxf(0,now-departure_at)
		# Retreat through the gaps between lanes and disappear into offshore fog
		# before reaching the reserve holding area. Wave two cannot intercept them.
		position=Vector3(lane_x+RETURN_LANE_OFFSET*smoothstep(0,10,t),0.12,LAND_Z+maxf(0,t-4)*8.0)
		rotation.y=PI*smoothstep(0,8,t)
		rotation.z=0
		return
	var landing_time=APPROACH_SECONDS+wave*SECOND_WAVE_DELAY
	var start=landing_time-APPROACH_SECONDS
	if now<start:
		# All reserve helms follow the same turn: neighbouring craft stay 12 m apart.
		var angle=now*0.09
		position=Vector3(lane_x+sin(angle)*3,0.12,HOLD_Z+cos(angle)*3)
		rotation.y=-angle
	else:
		var f=clampf((now-start)/APPROACH_SECONDS,0,1)
		position=Vector3(lane_x,0.12,lerpf(APPROACH_Z if wave==0 else HOLD_Z,LAND_Z,f))
		rotation.y=0
	if not stopped:
		position.y+=sin(now*2.1+index)*0.08
		rotation.z=sin(now*1.3+index)*0.011

func tick(delta:float):
	if departed:return
	update_course(game.elapsed)
	if departing:
		ramp.rotation.x=move_toward(ramp.rotation.x,0,delta)
		wake.show()
		if position.z>EXIT_Z:
			if game.player.truck==self:game.missed_landing()
			departed=true
			hide()
			for panel in parts:panel.collision_layer=0
			for actor in crew:
				actor.staged=true
				actor.hide()
				actor.collision_layer=0
				actor.equipment.collision_layer=0
				actor.set_physics_process(false)
			if engine_loop!=null:engine_loop.stop()
			return
	var at=APPROACH_SECONDS+wave*SECOND_WAVE_DELAY
	if game.elapsed>=at and not arrived:
		arrived=true
		stopped=true
		landed_at=at
		game.boat_landed(self)
	if arrived and not departing:
		ramp.rotation.x=move_toward(ramp.rotation.x,-PI*0.52,delta*0.96)
		wake.hide()
		for actor in occupants:
			if actor.alive and actor.truck==self and seat_transform(actor.seat).origin.z<position.z-6.8:actor.dismount()
		# The player walks down the open ramp; only AI passengers auto-disembark.
		unloaded=not has_passengers()
		if (unloaded and game.elapsed>landed_at+24) or (not occupants.any(func(a):return a.alive and a.truck==self) and game.elapsed>landed_at+36):
			departing=true
			departure_at=game.elapsed
			if engine_loop!=null:engine_loop.play()
	# The offshore reserve is concealed and cannot be targeted. Its crowded
	# passenger transforms need not all be rewritten sixty times per second.
	if wave==1 and game.elapsed<SECOND_WAVE_DELAY and game.elapsed<passenger_pose_at:return
	passenger_pose_at=game.elapsed+0.10
	for actor in occupants:
		if actor.alive and actor.truck==self:
			actor.global_transform=seat_transform(actor.seat)
			if arrived:
				actor.velocity=Vector3(0,0,-2.55)
				if actor.animate_model:
					actor.move_clock+=delta*5
					actor.model.legs[0].rotation.x=sin(actor.move_clock)*0.4
					actor.model.legs[1].rotation.x=-actor.model.legs[0].rotation.x
	for i in range(crew.size()):
		if crew[i].alive:
			crew[i].global_position=crew_transform(i).origin
			if not crew[i].mounted:crew[i].rotation.y=rotation.y

func has_passengers()->bool:
	if game.player.truck==self:return true
	for actor in occupants:
		if actor.alive and actor.truck==self:return true
	return false

func target_point(shooter)->Vector3:
	# Aim at the nearest occupied bay panel; hull wear can expose actual passengers.
	var nearest=to_global(Vector3(0,0.95,-3.5))
	var distance=INF
	for actor in occupants:
		if not actor.alive or actor.truck!=self:continue
		var p=actor.aim_point()
		var d=shooter.position.distance_squared_to(p)
		if d<distance:
			distance=d
			nearest=p
	if game.player.truck==self:
		var p=game.player.aim_point()
		if shooter.position.distance_squared_to(p)<distance:nearest=p
	return nearest

func dismount(_reason:String="orders"):
	# F cannot bypass the packed crew or open the ramp at sea.
	if not arrived:game.toast("HOLD FAST • THE COXSWAIN WILL DROP THE RAMP",3)
	else:game.toast("FOLLOW THE FILE • THE RAMP IS DOWN",3)

func receive_part_damage(amount:float,_point:Vector3,_explosive:bool,_part=null):
	total_damage+=amount
