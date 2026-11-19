## One Higgins-style landing craft for the Omaha mission: hull panels, ramp,
## scripted approach, passenger seating, unloading and departure.
##
## Role: 40 are created by omaha/battle.gd (20 per wave); the controller sets
## `game`, `index`, `wave`, `lane_x` and fills `occupants` (27 riflemen incl.
## engineers) and `crew` (3). Like the trucks in Ardennes the boat is moved
## by script, not physics: each frame update_course() sets its position from
## the game clock.
## Timeline per boat: wave 0 holds offshore (z about 430), approaches over
## APPROACH_SECONDS (32 s) to LAND_Z (20), drops the ramp, waits for the
## troops to leave, then reverses out to sea and disappears at EXIT_Z. Wave 1
## starts the same cycle SECOND_WAVE_DELAY (120 s) later.
## The hull is made of armor.gd panels with real hit points, so craft can be
## shot up; the crew is protected by a small shield, not invulnerable.
extends Node3D
const Art=preload("res://scripts/art.gd")
const Armor=preload("res://scripts/omaha/armor.gd")

## Duration (s) of the final run-in from the approach point to the beach.
const APPROACH_SECONDS:float=32.0

## z where the craft grounds (20 m in the surf).
const LAND_Z:float=20.0

## Seconds between the landing times of wave 1 and wave 2.
const SECOND_WAVE_DELAY:float=120.0

## The Omaha battle controller.
var game

## Craft number 0..39; used for the hull number and wobble phase.
var index:int=0

## 0 for the first wave, 1 for the second.
var wave:int=0

## x of the craft's lane.
var lane_x:float=0

## Passenger soldiers (27).
var occupants:Array=[]

## Coxswain and two gunners (3); crew[2] stands at the stern.
var crew:Array=[]

## Hull armour panels.
var parts:Array=[]

## Hinged front ramp; rotates from raised (0) to lowered (-0.52 PI).
var ramp:Node3D

## True once it has landed (no more bobbing).
var stopped:bool=false

## True when nobody is left aboard.
var unloaded:bool=false

## True from the moment it lands.
var arrived:bool=false

## Reserved; unused (craft are only disabled in this version).
var destroyed:bool=false

## Reserved; unused.
var disabled:bool=false

## Game time of landing, or -1.
var landed_at:float=-1

## Reserved; unused.
var dismount_reason:String=""

## Structural hit points (12000); damage is tracked but does not sink the boat.
var health:float=12000

## Count of bullets hitting the hull (statistic).
var bullet_hits:int=0

## Total damage the hull took (statistic).
var total_damage:float=0

## Engine sound player, or null.
var engine_loop=null

## Foam strip behind the craft; hidden while it is on the beach.
var wake:MeshInstance3D

## Game time at which the craft started leaving.
var departure_at:float=-1

## True while reversing out to sea.
var departing:bool=false

## True once the craft is gone (hidden, collisions off, crew frozen).
var departed:bool=false

## Next time the passengers' transforms are rewritten (throttled for the reserve).
var passenger_pose_at:float=-1

## Sideways drift (m) when leaving, so the craft pass between the incoming lanes.
const RETURN_LANE_OFFSET:float=6.0

## z of the offshore holding area (430).
const HOLD_Z:float=430.0

## z where wave 0 starts its run-in (270).
const APPROACH_Z:float=270.0

## z at which a departing craft is removed (330).
const EXIT_Z:float=330.0

## Godot lifecycle hook: builds the hull (floor, 12 side sections, bow plate, engine hood, ramp with bars, rails, hull numbers "PA 26-nn", coxswain's shield and wheel), the wake and finishes by merging box visuals into MultiMeshes (excluding the ramp and wake).
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

## Adds one hull armour panel (an Armor with a box collider, flagged hull_panel and on layer 128 too so AI can recognise vessel hits).
## [param size] box size. [param p] local position. [param mat] material. [param strength] hit points. [param parent] parent node (the ramp for ramp panels).
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

## World transform of passenger seat `seat`: three per row (x -0.8, 0, +0.8), rows 0.78 m apart along the bay. After landing each row slides toward the ramp 2.55 m/s with a 0.36 s stagger per row (up to z = -6.95), so troops file off in order.
func seat_transform(seat:int)->Transform3D:
	var row=int(seat/3)
	var p=Vector3((seat%3-1)*0.80,0.27,-4.25+row*0.78)
	if landed_at>=0:
		var t=maxf(0,game.elapsed-landed_at-1.5-row*0.36)
		p.z=maxf(-6.95,p.z-t*2.55)
	return global_transform*Transform3D(Basis.IDENTITY,p)

## World transform of crew slot 0/1 (gunners at the sides) or 2 (coxswain at the stern).
func crew_transform(slot:int)->Transform3D:
	return global_transform*Transform3D(Basis.IDENTITY,Vector3(0 if slot==2 else (-1.12 if slot==0 else 1.12),0.38,4.4 if slot==2 else 3.35))

## Sets the craft's position and yaw from game time `now`: circles slowly offshore before its time, runs in over 32 s, bobs on the swell (±8 cm, tiny roll) until grounded, and when departing reverses
## and turns 180 degrees while drifting sideways into the gap between lanes.
## [param now] game.elapsed in seconds.
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

## Per-tick update called by the battle controller: moves the craft, lowers the ramp on arrival (about 3.3 s), lets AI passengers off when their seat passes the ramp, decides when to depart (everyone out for 24 s, or 36 s after the last occupant died), removes the departed craft, keeps passengers glued to their seats and animates their legs.
## [param delta] physics step in seconds.
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
	# The second-wave craft are concealed offshore until they approach, so their crowded passenger transforms need only update ten times a second.
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

## True if the player or any living soldier is still aboard.
func has_passengers()->bool:
	if game.player.truck==self:return true
	for actor in occupants:
		if actor.alive and actor.truck==self:return true
	return false

## World point German gunners aim at: the nearest occupied passenger (or the bay panel when empty), so damaged plating can expose real people.
## [param shooter] the actor that will shoot (decides which is nearest).
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

## Passengers cannot leave by F: it only shows a toast (hold fast until the ramp is down, then follow the file).
func dismount(_reason:String="orders"):
	# F cannot bypass the packed crew or open the ramp at sea.
	if not arrived:game.toast("HOLD FAST • THE COXSWAIN WILL DROP THE RAMP",3)
	else:game.toast("FOLLOW THE FILE • THE RAMP IS DOWN",3)

## Records hull damage from an armour panel (accumulates total_damage).
func receive_part_damage(amount:float,_point:Vector3,_explosive:bool,_part=null):
	total_damage+=amount
