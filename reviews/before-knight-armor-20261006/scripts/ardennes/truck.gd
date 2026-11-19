# ==============================================================================
# Program: truck.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for truck.gd.
# ==============================================================================
## Armoured troop truck in the Ardennes convoy.
##
## Nine instances drive along the road spline (`progress` in metres from the start, see
## world.road_point). Each is built from damageable armour panels (armored_panel.gd), six
## wheels with separate health, and seat transforms for 12 passengers. The truck steers around
## disabled trucks, stops at the road end (progress 665), is declared stuck if it barely moves,
## and drops its passengers when disabled, stuck, arrived, wrecked or when its crew is gone.
## `game` (the Ardennes battle controller) sets `index` and calls `tick()` each physics step.
extends Node3D

# Art helpers, armour panel class and the weapon kit (soldier models for the cab crew).
const Art=preload("res://scripts/art.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")

# If the truck moves less than MIN_PROGRESS metres in a 6 s window, it counts as stuck.
const STUCK_SECONDS=6.0

# 3.05 m is chosen as the least movement (about ten feet) that still counts as driving during one stuck window.
const MIN_PROGRESS=3.05 # about ten feet, measured over the window above

# Progress value (metres along the road) where the convoy stops.
const END_PROGRESS=665.0

# Battle controller.
var game

# Truck number 0..8 (truck 4 carries the player).
var index:int=0

# Distance along the road in metres, and speed in m/s.
var progress:float=0
var speed:float=0
var health:float=900

# State flags: destroyed (wrecked), stopped (halted), disabled (cannot move), unloaded (passengers are out), arrived (reached the road end).
var destroyed:bool=false
var stopped:bool=false
var disabled:bool=false
var unloaded:bool=false
var arrived:bool=false

# Why the troops dismounted (for the HUD / test report).
var dismount_reason:String=""

# Sideways offset from the road centre line, and the lane it is moving to (0 = centre, +/-3.5 = passing lane).
var lane_offset:float=0
var desired_lane:float=0

# Progress value after which the truck may return to the centre lane.
var pass_until:float=-1

# How many times this truck tried to go around an obstruction (used by tests).
var bypass_attempts:int=0

# Index of the truck currently blocking it, to count each obstruction once.
var blocked_by=-1

# Stuck detection window: elapsed time and where the window started.
var travel_window:float=0
var window_origin:Vector3

# Passengers (soldiers), armour panels, wheel panels, and per-wheel health (600 each).
var occupants:Array=[]
var parts:Array=[]
var wheels:Array=[]
var wheel_health:Array[float]=[105,105,105,105,105,105]

# Looping engine sound player, if any.
var engine_loop:AudioStreamPlayer3D

# Statistics: total damage taken, bullets that hit, time of the last hit.
var total_damage:float=0
var bullet_hits:int=0
var last_hit_time:float=-100

# Offset (relative to the truck) used when aiming at its centre.
var target_bias:Vector3=Vector3(0,1.8,0.7)

# Caches of the last transform inputs, so update_transform() skips unchanged frames.
var last_transform_progress:float=-100
var last_transform_lane:float=-100

## Build chassis, engine, cab, troop compartment, wheels and tail gate from armour panels.
func _ready():
	# Materials: olive paint, wood benches, dark steel and rubber.
	var olive=Art.material(Color("535c43"),0.18,0.83)
	var wood=Art.material(Color("655d46"))
	var steel=Art.material(Color("333b38"),0.68,0.61)
	var rubber=Art.material(Color("202423"))
	var canvas=Art.material(Color("727258"),0.0,0.96)
	# Chassis, floor, engine block and cab. Each part() call creates a collidable, damageable panel with a role tag.
	part(Vector3(2.15,0.28,6.2),Vector3(0,0.85,0),steel,"metal","chassis")
	part(Vector3(2.2,0.16,3.9),Vector3(0,1.31,0.91),wood,"wood","floor")
	part(Vector3(1.7,0.68,1.50),Vector3(0,1.43,-2.25),olive,"metal","engine")
	part(Vector3(2.2,0.6,1.35),Vector3(0,1.35,-1.35),olive,"metal","cab")
	part(Vector3(2.17,0.14,1.35),Vector3(0,2.52,-1.39),olive,"metal","cab")
	# Per side: cab door, side armour, bench, upper armour, roof hoops and three wheels.
	for x in [-1.07,1.07]:
		part(Vector3(0.07,0.92,1.30),Vector3(x,1.86,-1.34),olive,"metal","cab")
		part(Vector3(0.11,0.82,3.87),Vector3(x,1.85,0.97),wood,"wood","side")
		part(Vector3(0.34,0.13,3.50),Vector3(x*0.79,1.68,1),wood,"wood","bench")
		# Covered troop bed: side curtains, front curtain and roof; rear stays open.
		part(Vector3(0.045,1.10,3.90),Vector3(x,2.71,0.98),canvas,"cloth","canvas")
		for z in [-0.86,0.38,1.65,2.90]:
			part(Vector3(0.045,1.64,0.045),Vector3(x,2.4,z),olive,"metal","hoop")
		# Wheels are panels so bullets can hit them; each remembers its index in wheel_health and is drawn with a rotating tyre and hub instead of the default box.
		for z in [-2.25,1.08,2.25]:
			var wheel=part(Vector3(0.34,1.1,1.1),Vector3(x*1.11,0.62,z),rubber,"metal","wheel")
			wheel.set_meta("wheel_index",wheels.size())
			for mesh in wheel.owned_meshes():mesh.queue_free()
			var tire=Art.cylinder(wheel,0.56,0.34,Vector3.ZERO,rubber,-1,12)
			tire.rotation.z=PI/2
			var disk=Art.cylinder(wheel,0.27,0.36,Vector3.ZERO,olive,-1,10)
			disk.rotation.z=PI/2
			wheels.append(wheel)
	part(Vector3(2.2,0.055,3.98),Vector3(0,3.28,0.96),canvas,"cloth","canvas")
	part(Vector3(2.12,1.10,0.045),Vector3(0,2.71,-0.98),canvas,"cloth","canvas")
	part(Vector3(2.17,0.78,0.10),Vector3(0,1.81,2.91),wood,"wood","tailgate")
	# Front lamps.
	for x in [-0.88,0.88]:
		Art.box(self,Vector3(0.20,0.20,0.055),Vector3(x,1.63,-3.05),Art.material(Color("dbd1a9")))
	# Cab crew are visual vehicle crew; the combat passengers have individual health.
	# Cab crew are visual vehicle crew; the combat passengers have individual health.
	for x in [-0.51,0.51]:
		var driver=Kit.soldier(self,1,index)
		driver.root.position=Vector3(x,0.40,-1.32)
		for leg in driver.legs:leg.hide()
	# Place the truck on the road, then merge same-material boxes into draw batches (wheels excluded because they spin).
	update_transform()
	window_origin=position

## Create one damageable panel as a child.
## @param size Box size (m). @param offset Local position. @param mat Material.
## @param kind Material kind ("metal" or "wood"). @param role Tag stored as meta "truck_role" (armor, wheel, engine, cab...).
## @return The new panel.
func part(size:Vector3,offset:Vector3,mat:Material,kind:String,role:String):
	var body=game.world.solid(size,offset,mat,kind,self)
	body.truck_owner=self
	body.set_meta("truck_role",role)
	parts.append(body)
	return body

## World transform of a passenger seat: two benches facing each other, 0.6 m apart per row.
## @param seat Seat index; even seats on the left, odd on the right.
func seat_transform(seat:int)->Transform3D:
	var side=-1 if seat%2==0 else 1
	var offset=Vector3(side*0.70,1.32,-0.45+float(seat/2)*0.60)
	return global_transform*Transform3D(Basis(Vector3.UP,-side*PI/2),offset)

## Transform of the rear-facing gunner position (seat 1).
func gunner_transform()->Transform3D:
	return seat_transform(1)

## Whether anyone alive (including the player) is still aboard.
func has_passengers()->bool:
	if unloaded:return false
	if game.player.truck==self and game.player.health>0:return true
	for actor in occupants:
		if actor.alive and actor.truck==self:return true
	return false

## Choose a point on this truck for an enemy to aim at.
## @param shooter The firing soldier; his index and the clock spread the bursts across panels.
func target_point(shooter)->Vector3:
	# Finite bursts move between targets and panels; wheel hits are real ray hits.
	# Finite bursts move between targets and panels; wheel hits are real ray hits.
	var choice=(shooter.index+int(game.elapsed/2.2))%10
	if choice==0:
		var wheel=wheels[(shooter.index+int(game.elapsed))%wheels.size()]
		return wheel.global_position
	var side=signf(to_local(shooter.global_position).x)
	if choice<3:return to_global(Vector3(side*0.9,1.75,-2.0))
	return to_global(Vector3(side*1.08,2.15,0.25+float(choice%4)*0.62))

## Move the truck to its place on the road and align it to the slope and heading.
func update_transform():
	# Skip all work when neither progress nor lane changed since the last call.
	if is_equal_approx(progress,last_transform_progress) and is_equal_approx(lane_offset,last_transform_lane):return
	last_transform_progress=progress
	last_transform_lane=lane_offset
	position=game.world.road_point(progress)
	var ahead=game.world.road_point(progress+1)
	var heading=(ahead-position).normalized()
	var right=heading.cross(Vector3.UP).normalized()
	# Right-hand side offset applies the lane shift.
	position+=right*lane_offset
	# Sit on the terrain surface.
	position.y=game.world.surface_height(position.x,position.z)
	rotation.y=atan2(-heading.x,-heading.z)
	# Pitch follows the road, limited to +/-0.16 rad so the truck never tips over.
	rotation.x=-asin(clampf(heading.y,-0.16,0.16))

## Whether a lane is free and flat enough to overtake.
## @param lane Sideways offset in metres.
func can_pass(lane:float)->bool:
	for other in game.trucks:
		if other==self:continue
		# Another truck within 11 m along the road and 2.7 m sideways occupies the lane.
		if absf(other.progress-progress)<11 and absf(other.lane_offset-lane)<2.7:return false
	var at=game.world.road_point(progress+8)
	at.x+=lane
	# The ground 8 m ahead must be within 1 m of the road height, so the passing lane is drivable.
	return absf(game.world.surface_height(at.x,at.z)-game.world.road_point(progress+8).y)<1.0

## Per-physics-step driving logic.
## @param delta Seconds. @param _front Unused.
func tick(delta:float,_front=null):
	if destroyed or unloaded:return
	# Nobody aboard (everyone died): hand over to dismount().
	if not has_passengers():
		dismount("crew lost")
		return
	# Target speed 8.2 m/s (about 30 km/h), 68 % with one flat tyre, zero when two wheels are flat or the hull is gone.
	var target_speed=8.2
	var flats=wheel_health.filter(func(h):return h<=0).size()
	disabled=flats>=2 or health<=0
	if flats==1:target_speed*=0.68
	if disabled or arrived:target_speed=0
	# Find the closest truck ahead within 18 m in the same lane.
	var obstruction=null
	var gap=INF
	for other in game.trucks:
		if other==self:continue
		var ahead=other.progress-progress
		if ahead>0 and ahead<18 and absf(other.lane_offset-lane_offset)<2.7 and ahead<gap:
			obstruction=other
			gap=ahead
	# An obstruction that is nearly stopped, disabled, wrecked or unloaded: try the left, then right, passing lane and note when to return.
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
		# Brake: stop within 10 m, otherwise match the speed of the truck in front when closer than 15 m.
		if gap<10 and absf(lane_offset-obstruction.lane_offset)<2.7:target_speed=0
		elif gap<15:target_speed=minf(target_speed,maxf(1,obstruction.speed))
	# Return to the centre once past the obstruction and the lane is free.
	elif progress>pass_until and desired_lane!=0 and can_pass(0):desired_lane=0
	# Lane changes at 1.9 m/s; acceleration 2.2 m/s^2, braking 4.0 m/s^2.
	lane_offset=move_toward(lane_offset,desired_lane,delta*1.9)
	speed=move_toward(speed,target_speed,delta*(4.0 if target_speed<speed else 2.2))
	# Disabled trucks stay put; others advance (never beyond the road end).
	if not disabled:
		progress=minf(END_PROGRESS,progress+speed*delta)
		update_transform()
	# Arrival at the end of the road.
	if progress>=END_PROGRESS-0.05:
		arrived=true
		stopped=true
		speed=0
	# Spin the tyre meshes so rolling matches the speed (wheel radius 0.56 m).
	for wheel in wheels:
		for mesh in wheel.get_children():
			if mesh is MeshInstance3D:mesh.rotate_y(speed*delta/0.56)
	# Stuck detection every 6 s: less than 3.05 m moved means the troops dismount with a reason.
	travel_window+=delta
	if travel_window>=STUCK_SECONDS:
		var moved=position.distance_to(window_origin)
		travel_window=0
		window_origin=position
		if moved<MIN_PROGRESS:
			dismount("arrival" if arrived else ("wheels disabled" if disabled else "stuck"))

## Take damage on a part.
## @param amount Damage points. @param point World hit point (unused here).
## @param explosive true for blasts. @param part_node The hit panel, used for its role/wheel index.
func receive_part_damage(amount:float,point:Vector3,explosive:bool,part_node=null):
	if destroyed:return
	total_damage+=amount
	last_hit_time=game.elapsed
	# Only bullets are counted as hits (for reports).
	if not explosive:bullet_hits+=1
	# Wheel hits go to that wheel (explosions are four times as effective as bullets); a ruined wheel is drawn flattened.
	if part_node!=null and part_node.has_meta("wheel_index"):
		var wheel_index=int(part_node.get_meta("wheel_index"))
		wheel_health[wheel_index]=maxf(0,wheel_health[wheel_index]-amount)
		if wheel_health[wheel_index]==0:
			for mesh in wheels[wheel_index].get_children():
				if mesh is MeshInstance3D:mesh.scale=Vector3(1,0.60,1)
		# Two or more ruined wheels disable the truck.
		disabled=wheel_health.filter(func(h):return h<=0).size()>=2
		return
	var role=part_node.get_meta("truck_role","") if part_node!=null else ""
	var harm=amount*(0.22 if role=="engine" else 0.006)
	if explosive:harm=amount*0.65
	health=maxf(0,health-harm)
	if health<=0:wreck(false)

## Wreck the truck: scorch the visuals, injure and eject the passengers, burn and leave an obstacle.
## @param scripted true when the wreck was ordered by the ambush script.
func wreck(scripted:bool):
	if destroyed:return
	destroyed=true
	disabled=true
	health=0
	speed=0
	stopped=true
	rotation.z=randf_range(-0.10,0.10)
	game.vehicle_wrecked(self,scripted)
	for item in parts:
		if item.get_meta("truck_role","")=="canvas":item.demolish()
	# Burnt-black material applied to all panels and batches.
	var scorch=Art.material(Color("292a25"),0.3,0.92)
	for item in parts:
		for mesh in item.owned_meshes():mesh.material_override=scorch
	# Fire at the engine bay.
	game.add_wreck_fire(global_position+Vector3(0,1.7,-1.9))
	# Passengers take 24-48 damage and get out if still alive; the player takes 45.
	for actor in occupants.duplicate():
		if actor.alive and actor.truck==self:actor.take_damage(randf_range(108,155),global_position,"explosion")
	if game.player.truck==self:game.player.take_damage(140,position,"explosion")
	game.world.obstacles.append({"p":global_position,"r":3.4,"node":parts[0]})
	game.world.geometry_updated(global_position)
	unloaded=true

## Order everyone out of the truck.
## @param reason Text kept in `dismount_reason` ("crew lost", "stuck", "wheels disabled", "arrival", ...).
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
