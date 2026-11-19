# ==============================================================================
# Program: field_navigation.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for field_navigation.gd.
# ==============================================================================
## Local walkable-ground graph for AI pathfinding (A* over a grid sampled from physics).
##
## Samples a 71 x 75 grid of 2 m cells around the village by raycasting down and testing a
## soldier-sized capsule for obstacles, then links neighbouring cells. The graph is
## refreshed in small patches when doors open or walls/ground change (battle world calls
## `mark_dirty`). AI scripts call `path_between`, `floor_point` and `line_clear`.
## Built asynchronously across several physics frames to avoid a loading hitch.
extends Node3D

# A small tactical ground graph, refreshed locally when a door moves or geometry
# changes. It is sampled from live collision, including the floors of dug trenches.
# Grid bounds in cell units (inclusive). World coordinates = cell * STEP.
# A small tactical ground graph, refreshed locally when a door moves or geometry
# changes. It is sampled from live collision, including the floors of dug trenches.
const MIN_CELL=Vector2i(-35,-44)
const MAX_CELL=Vector2i(35,30)

# Cells per row: MAX.x - MIN.x + 1, used to turn (x, z) into an AStar id.
const WIDTH=71

# Cell size in metres.
const STEP=2.0

# The AStar3D graph; ids come from id_for().
var graph=AStar3D.new()

# False until the first build finishes; path queries return empty until then.
var ready_for_paths: bool=false

# True during build/refresh so no second refresh starts.
var rebuilding: bool=false

# Cells waiting for refresh (Vector2i -> true).
var dirty: Dictionary={}

# Delay in seconds after the last mark_dirty before refreshing, to merge bursts of changes.
var cooldown: float=0

# Capsule matching a soldier (0.36 m radius, 1.82 m tall) for clearance tests.
var probe: CapsuleShape3D

# Incremented after every build or refresh so listeners can invalidate cached paths.
var revision: int=0

# Collider RIDs of closed doors, ignored when testing line-of-travel between cells.
var door_rids: Array[RID]=[]

## Prepare the clearance probe and schedule the initial build after the scene is ready.
func _ready():
	probe=CapsuleShape3D.new()
	probe.radius=0.36
	probe.height=1.82
	# Deferred so physics bodies of the level exist before sampling.
	call_deferred("build")

## Cell to AStar point id (row-major).
func id_for(cell: Vector2i) -> int:
	return cell.x-MIN_CELL.x+(cell.y-MIN_CELL.y)*WIDTH

## Whether a cell lies within the grid.
func inside(cell: Vector2i) -> bool:
	return cell.x>=MIN_CELL.x and cell.x<=MAX_CELL.x and cell.y>=MIN_CELL.y and cell.y<=MAX_CELL.y

## Sample ground at one cell and enable/disable its graph point.
## @param cell Grid cell.
func sample(cell: Vector2i):
	var x=cell.x*STEP
	var z=cell.y*STEP
	var space=get_world_3d().direct_space_state
	# Ray from 2.2 m above to 23 m below, hitting only the world layer (1); the large drop finds trench floors.
	var query=PhysicsRayQueryParameters3D.create(Vector3(x,2.20,z),Vector3(x,-23,z),1)
	var hit=space.intersect_ray(query)
	var point=Vector3(x,0,z)
	# Slopes steeper than about 49 degrees (normal.y <= 0.65) are not walkable.
	var valid=not hit.is_empty() and hit.normal.y>0.65
	if valid:
		# Place the point just above the surface.
		point=hit.position+Vector3(0,0.04,0)
		# Check a standing capsule (centre 0.93 m above the ground) for obstacles.
		var shape_query=PhysicsShapeQueryParameters3D.new()
		shape_query.shape=probe
		shape_query.transform=Transform3D(Basis.IDENTITY,point+Vector3(0,0.93,0))
		shape_query.collision_mask=1
		for obstacle in space.intersect_shape(shape_query,12):
			# Soldiers can open a door along a planned route.
			# Soldiers can open a door along a planned route.
			if obstacle.collider.get_parent().is_in_group("field_door") and not obstacle.collider.get_parent().opened:continue
			valid=false
			break
	# Create or reuse the point, then enable or disable it depending on validity.
	var id=id_for(cell)
	if graph.has_point(id):graph.set_point_position(id,point)
	else:graph.add_point(id,point)
	graph.set_point_disabled(id,not valid)

## Connect a cell to its eight neighbours where movement is possible.
## @param cell Grid cell.
func link(cell: Vector2i):
	var source=id_for(cell)
	for dx in range(-1,2):
		for dz in range(-1,2):
			if dx==0 and dz==0:continue
			var neighbour=cell+Vector2i(dx,dz)
			if not inside(neighbour):continue
			var destination=id_for(neighbour)
			var allowed=not graph.is_point_disabled(source) and not graph.is_point_disabled(destination)
			# Steps taller than 0.85 m between neighbours are not allowed.
			allowed=allowed and absf(graph.get_point_position(source).y-graph.get_point_position(destination).y)<0.85
			# Diagonals also need both orthogonal neighbours open, so paths do not cut wall corners.
			if dx!=0 and dz!=0:
				allowed=allowed and not graph.is_point_disabled(id_for(cell+Vector2i(dx,0))) and not graph.is_point_disabled(id_for(cell+Vector2i(0,dz)))
			if allowed:
				# Line-of-travel check at chest height (0.65 m) to catch thin walls between cells.
				var a=graph.get_point_position(source)+Vector3(0,0.65,0)
				var b=graph.get_point_position(destination)+Vector3(0,0.65,0)
				var ray=PhysicsRayQueryParameters3D.create(a,b,1)
				# Closed doors are ignored because soldiers open them.
				ray.exclude=door_rids
				allowed=get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
			# Only touch the graph when the connection state changed.
			var connected=graph.are_points_connected(source,destination)
			if allowed and not connected:graph.connect_points(source,destination)
			elif not allowed and connected:graph.disconnect_points(source,destination)

## Build the whole graph in the background (coroutine).
func build():
	rebuilding=true
	# Wait three physics frames so every level collider is registered.
	for i in range(3):
		await get_tree().physics_frame
		if not is_inside_tree():return
	update_doors()
	var count=0
	for z in range(MIN_CELL.y,MAX_CELL.y+1):
		for x in range(MIN_CELL.x,MAX_CELL.x+1):
			sample(Vector2i(x,z))
			count+=1
		# Yield every 420 cells (a handful of rows) to keep each frame cheap.
		if count>=420:
			count=0
			await get_tree().physics_frame
			if not is_inside_tree():return
	# Link only after all cells are sampled so neighbours have valid positions and states.
	for z in range(MIN_CELL.y,MAX_CELL.y+1):
		for x in range(MIN_CELL.x,MAX_CELL.x+1):link(Vector2i(x,z))
	ready_for_paths=true
	rebuilding=false
	revision+=1

## Record which doors are closed.
func update_doors():
	door_rids.clear()
	for door in get_tree().get_nodes_in_group("field_door"):
		# Only closed doors block movement.
		if not door.opened:door_rids.append(door.leaf.get_rid())

## Flag the area around a world point for resampling (called when geometry changes).
## @param point World position.
func mark_dirty(point: Vector3):
	dirty[Vector2i(roundi(point.x/STEP),roundi(point.z/STEP))]=true
	# Wait 0.15 s so several changes can be processed together.
	cooldown=0.15

## Start a refresh when changes are pending and the cooldown has expired.
func _physics_process(delta):
	cooldown=maxf(0,cooldown-delta)
	if ready_for_paths and not rebuilding and not dirty.is_empty() and cooldown==0:
		refresh()

## Resample cells within 6 cells (12 m) of each dirty cell and relink them.
func refresh():
	rebuilding=true
	update_doors()
	var cells: Dictionary={}
	for centre in dirty:
		for x in range(-6,7):
			for z in range(-6,7):
				var cell=centre+Vector2i(x,z)
				if inside(cell):cells[cell]=true
	dirty.clear()
	var count=0
	for cell in cells:
		sample(cell)
		count+=1
		# Yield every 240 cells to avoid frame spikes.
		if count%240==0:
			await get_tree().physics_frame
			if not is_inside_tree():return
	for cell in cells:link(cell)
	revision+=1
	rebuilding=false

## Snap a position to the nearest graph point.
## @return The graph position, or the input if the graph is not ready.
func floor_point(point: Vector3) -> Vector3:
	if not ready_for_paths:return point
	var id=graph.get_closest_point(point)
	return graph.get_point_position(id) if id>=0 else point

## Find a path of ground points.
## @param start World start.
## @param destination World goal.
## @return Waypoints from start to goal, or an empty array if not ready or no point is found.
func path_between(start: Vector3, destination: Vector3) -> PackedVector3Array:
	if not ready_for_paths:return PackedVector3Array()
	var a=graph.get_closest_point(start)
	var b=graph.get_closest_point(destination)
	if a<0 or b<0:return PackedVector3Array()
	return graph.get_point_path(a,b,false)

## Line-of-sight test at a given height.
## @param height Metres above each endpoint (default 1.25, about eye level when crouched).
## @return true if no world geometry blocks the straight line.
func line_clear(start: Vector3, destination: Vector3, height: float=1.25) -> bool:
	var ray=PhysicsRayQueryParameters3D.create(start+Vector3(0,height,0),destination+Vector3(0,height,0),1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
