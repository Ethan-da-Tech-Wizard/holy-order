## One covered US cargo truck (CCKW-style) in the Ardennes convoy: its armoured
## body, driving behaviour, damage model and unloading of passengers.
##
## Role: nine are created by battle.gd's make_convoy(), which sets `game`,
## `index` and the starting `progress`, then fills `occupants` with the
## soldiers of its squad. The truck follows the road by a single scalar
## (`progress`, metres along the road centre line from world.road_point) and a
## lateral `lane_offset`, so no physics body drives it. Each tick it keeps a
## gap to the truck ahead, overtakes a stopped or disabled one by shifting 3.5 m
## to either side, and dismounts when stuck.
## Damage: the body is made of ArmoredPanel parts (each with a collider) and
## six wheels with their own health; flats slow it, two flats or 0 health disable it, and
## it can be wrecked (burning, scorched, occupants hurt).
## Visuals are batched into MultiMeshes (vehicle_visuals.gd) except the wheels.
extends Node3D

const Art=preload("res://scripts/art.gd")
const ArmoredPanel=preload("res://scripts/ardennes/armored_panel.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")

## Length (s) of the window over which movement is checked for a stuck truck.
const STUCK_SECONDS=6.0

## Minimum distance (m, about ten feet) the truck must cover within STUCK_SECONDS or its crew dismounts.
const MIN_PROGRESS=3.05 # about ten feet, measured over the window above

## Road distance (m) of the kill-zone stop where the convoy halts.
const END_PROGRESS=665.0

## The battle controller.
var game

## Truck number 0-8 (0 is the lead).
var index:int=0

## Distance along the road centre line in metres; increases toward the end.
var progress:float=0

## Current speed in m/s.
var speed:float=0

## Structural hit points (4500); the engine and explosions reduce it.
var health:float=4500

## True after wreck().
var destroyed:bool=false

## True when it has halted (arrived, wrecked or unloaded).
var stopped:bool=false

## True when two or more wheels are flat or health is zero; it cannot move.
var disabled:bool=false

## True once the passengers have been put out (no more passengers).
var unloaded:bool=false

## True when it reached END_PROGRESS.
var arrived:bool=false

## Why it unloaded: "orders", "ambush", "arrival", "stuck", "crew lost", ...
var dismount_reason:String=""

## Current sideways shift from the road centre (m).
var lane_offset:float=0

## Sideways shift it is moving toward (0 or +-3.5 when overtaking).
var desired_lane:float=0

## Road distance beyond which it may return to the centre lane after overtaking.
var pass_until:float=-1

## Times it started going around an obstacle (statistic).
var bypass_attempts:int=0

## Index of the truck currently blocking it, or -1.
var blocked_by=-1

## Seconds elapsed in the current stuck-check window.
var travel_window:float=0

## Position at the start of that window.
var window_origin:Vector3

## Soldiers assigned to this truck.
var occupants:Array=[]

## ArmoredPanel bodies that make up the vehicle.
var parts:Array=[]

## The six wheel panels.
var wheels:Array=[]

## Hit points of each wheel (600); flats reduce speed, two flats disable the truck.
var wheel_health:Array[float]=[600,600,600,600,600,600]

## Positional engine sound.
var engine_loop:AudioStreamPlayer3D

## Sum of all damage received (statistic).
var total_damage:float=0

## Number of non-explosive hits.
var bullet_hits:int=0

## game.elapsed of the last hit; Germans prefer trucks they hit recently.
var last_hit_time:float=-100

## Reserved aim offset; unused.
var target_bias:Vector3=Vector3(0,1.8,0.7)

## Cache for update_transform().
var last_transform_progress:float=-100

## Cache for update_transform().
var last_transform_lane:float=-100

## Godot lifecycle hook: builds the truck from armoured box parts (chassis,
## floor, engine, cab, troop compartment with bench seats, roof, tailgate with a
## rear viewing slit, wheels), cab crew and lamps, places it on the road and then merges the box visuals into MultiMeshes.
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

	# Side walls, benches, roof hoops and wheels are built once per side (x mirrored).
	for x in [-1.07,1.07]:
		part(Vector3(0.07,0.92,1.30),Vector3(x,1.86,-1.34),olive,"metal","cab")
		part(Vector3(0.16,0.82,3.87),Vector3(x,1.85,0.97),olive,"metal","armor")
		part(Vector3(0.34,0.13,3.50),Vector3(x*0.79,1.68,1),wood,"wood","bench")
		# Steel troop compartment, including roof and a narrow rear viewing slit.
		part(Vector3(0.14,1.10,3.90),Vector3(x,2.71,0.98),olive,"metal","armor")
		for z in [-0.86,0.38,1.65,2.90]:
			part(Vector3(0.045,1.64,0.045),Vector3(x,2.4,z),olive,"metal","hoop")

		# Three wheels per side (front, and two rear); the box part is the collider, replaced by a cylinder tyre and hub for looks.
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
	preload("res://scripts/vehicle_visuals.gd").batch_boxes(self,wheels)

## Adds one armour/body panel: an ArmoredPanel with a box mesh and a matching collider.
## [param size] box size (m). [param offset] position in truck space. [param mat] material.
## [param kind] material kind for damage ("metal" or "wood"). [param role] tag ("engine", "wheel", "chassis"...) kept as meta "truck_role".
## Returns the new panel.
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

## World transform of passenger seat `seat`: even seats on the left, odd on the right, two per bench row 0.6 m apart, facing out.
func seat_transform(seat:int)->Transform3D:
	var side=-1 if seat%2==0 else 1
	var offset=Vector3(side*0.70,1.32,-0.45+float(seat/2)*0.60)
	return global_transform*Transform3D(Basis(Vector3.UP,-side*PI/2),offset)

## Position for a gunner (seat 1); kept for compatibility.
func gunner_transform()->Transform3D:
	return seat_transform(1)

## True while anyone (the player or a living soldier) is still aboard.
func has_passengers()->bool:
	if unloaded:return false
	if game.player.truck==self and game.player.health>0:return true
	for actor in occupants:
		if actor.alive and actor.truck==self:return true
	return false

## Where `shooter` aims at this truck: the shooter's index and the clock choose
## between a wheel (10%), the cab (20%) and body panels, so a group of
## gunners spreads its fire over different parts, like finite bursts moving across the truck.
func target_point(shooter)->Vector3:
	# Finite bursts move between targets and panels; wheel hits are real ray hits.
	var choice=(shooter.index+int(game.elapsed/2.2))%10
	if choice==0:
		var wheel=wheels[(shooter.index+int(game.elapsed))%wheels.size()]
		return wheel.global_position
	var side=signf(to_local(shooter.global_position).x)
	if choice<3:return to_global(Vector3(side*0.9,1.75,-2.0))
	return to_global(Vector3(side*1.08,2.15,0.25+float(choice%4)*0.62))

## Puts the truck on the road: position from progress and lane_offset, terrain height, yaw to the road direction and a small pitch (limited to +-0.16). Skips work if neither changed.
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

## True if lane offset `lane` is free of other trucks within 11 m along the road and the ground there is level with the road (within 1 m).
func can_pass(lane:float)->bool:
	for other in game.trucks:
		if other==self:continue
		if absf(other.progress-progress)<11 and absf(other.lane_offset-lane)<2.7:return false
	var at=game.world.road_point(progress+8)
	at.x+=lane
	return absf(game.world.surface_height(at.x,at.z)-game.world.road_point(progress+8).y)<1.0

## Per-physics-tick driving logic. Speed target 8.2 m/s (about 30 km/h), 68%
## with one flat tyre, 0 when disabled or arrived. Finds the nearest truck ahead
## in the same lane within 18 m; if that truck is nearly stopped, overtakes using
## whichever side lane is free; otherwise slows to its speed inside 15 m and stops inside 10 m.
## Accelerates at 2.2 m/s^2 and brakes at 4. Spins wheels, checks arrival and the stuck window.
## [param delta] physics step in seconds. [param _front] unused.
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

	# Obstruction handling: a stopped, disabled or empty truck ahead is a
	# blocker to drive around; moving traffic is simply followed.
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

	# A truck that has not moved ten feet in six seconds is treated as stuck and its crew dismounts.
	if travel_window>=STUCK_SECONDS:
		var moved=position.distance_to(window_origin)
		travel_window=0
		window_origin=position
		if moved<MIN_PROGRESS:
			dismount("arrival" if arrived else ("wheels disabled" if disabled else "stuck"))

## Damage from a hit on one of the truck's parts.
## [param amount] damage points. [param point] hit position. [param explosive] blast flag.
## [param part_node] the panel hit. Wheels lose 8% of the damage (32% explosive)
## and shrink visually when flat; engine hits do 1.2% as structural damage, other
## parts 0.1%, explosions 18%; at 0 health the truck is wrecked.
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

## Reduces damage to passengers by the cover the truck gives: rifle fire 12%, explosions 22%, anything else full.
func passenger_damage(amount:float,kind:String)->float:
	if destroyed:return amount
	return amount*(0.12 if kind=="rifle" else (0.22 if kind=="explosion" else 1.0))

## Effect of the scripted rocket: heavy part damage (1400), then the truck is
## disabled and unloads, without killing everyone on board by script.
func receive_ambush_strike(point:Vector3):
	# A rocket can stop the convoy without a scripted execution of everyone aboard.
	receive_part_damage(1400,point,true)
	if destroyed:return
	disabled=true
	dismount("armored ambush stop")

## Destroys the truck: darkens all parts, adds a smoke fire, injures occupants
## (24-48 explosion damage each) and puts them out, injures the player (45) if aboard, registers a path obstacle for AI and tells the battle controller.
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
	for visual in get_children():
		if visual is MultiMeshInstance3D and visual.has_meta("vehicle_panel_batch"):visual.material_override=scorch
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

## Unloads everyone and tells the battle controller (which starts the dismounted phase on the first call). Safe to call twice.
## [param reason] label stored in dismount_reason.
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
