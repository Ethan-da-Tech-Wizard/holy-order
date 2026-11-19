## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/field_navigation.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Ground navigation graph for the desert village, used by enemy AI for pathing.
##
## Why not NavigationServer: the village is dynamic. Walls are destroyed, doors
## swing, trenches are dug, so the graph is sampled from live physics
## collision and refreshed locally around whatever changed.
##
## How it works: the map is a regular grid of cells STEP (2 m) apart covering
## MIN_CELL..MAX_CELL. Each cell becomes an AStar3D point whose position is the
## floor height found by a downward ray (so trench floors count). A point is
## disabled if the floor is too steep or a standing capsule would hit
## something. Neighbouring points (8 directions) are connected when both are
## walkable, the step height is under 0.85 m, diagonals do not cut corners, and
## a chest-high ray between them is clear (closed doors are ignored by the
## ray and by the capsule test because soldiers can open them).
##
## Callers: enemy.gd asks path_between() / floor_point() / line_clear();
## world.gd calls mark_dirty() whenever geometry changes. build() runs once
## after the scene is up, spreading its work over physics frames so there is no
## loading hitch. Layer mask 1 (static world) is used for every query.
extends Node3D

# A small tactical ground graph, refreshed locally when a door moves or geometry
# changes. It is sampled from live collision, including the floors of dug trenches.

## Lowest grid cell (x, z index) covered, in STEP units: -70 m, -88 m.
const MIN_CELL=Vector2i(-35,-44)

## Highest grid cell: +70 m, +60 m. Together they cover the whole village.
const MAX_CELL=Vector2i(35,30)

## Cells per row (MAX.x - MIN.x + 1), used to turn (x, z) into a unique point id.
const WIDTH=71

## Grid spacing in metres; a trade-off between path detail and sampling cost.
const STEP=2.0

## The A* graph itself; points are keyed by id_for(cell).
var graph=AStar3D.new()

## False until the first full build finishes; queries return empty results
## until then, so the AI falls back to direct movement.
var ready_for_paths: bool=false

## True while build()/refresh() is mid-way; stops overlapping rebuilds.
var rebuilding: bool=false

## Set of cells reported by mark_dirty() since the last refresh (value unused).
var dirty: Dictionary={}

## Seconds to wait after the latest change before refreshing, so a burst of
## explosions triggers a single refresh instead of many.
var cooldown: float=0

## Capsule (0.36 m radius, 1.82 m high) approximating a standing soldier; used
## to test whether a cell is clear of obstacles.
var probe: CapsuleShape3D

## Counter incremented after each rebuild; AI can compare it to know that a
## cached path might be stale.
var revision: int=0

## Collision RIDs of currently closed doors, excluded from line-of-walk rays.
var door_rids: Array[RID]=[]

## Godot lifecycle hook: creates the probe shape and schedules the first
## build after the rest of the scene has finished entering the tree (physics
## bodies need a frame before they can be queried).
func _ready():
	probe=CapsuleShape3D.new()
	probe.radius=0.36
	probe.height=1.82
	call_deferred("build")

## Maps a grid cell to its unique AStar point id (row-major from MIN_CELL).
func id_for(cell: Vector2i) -> int:
	return cell.x-MIN_CELL.x+(cell.y-MIN_CELL.y)*WIDTH

## True if `cell` lies within the MIN_CELL..MAX_CELL rectangle.
func inside(cell: Vector2i) -> bool:
	return cell.x>=MIN_CELL.x and cell.x<=MAX_CELL.x and cell.y>=MIN_CELL.y and cell.y<=MAX_CELL.y

## Probes the physics world for one cell and creates or updates its graph point.
## [param cell] grid index. Ray goes from 2.2 m above to 23 m below the cell
## centre, which finds floors down in trenches. A floor with normal.y <= 0.65
## (steeper than about 49 degrees) is rejected as a wall or cliff.
func sample(cell: Vector2i):
	var x=cell.x*STEP
	var z=cell.y*STEP
	var space=get_world_3d().direct_space_state
	var query=PhysicsRayQueryParameters3D.create(Vector3(x,2.20,z),Vector3(x,-23,z),1)
	var hit=space.intersect_ray(query)
	var point=Vector3(x,0,z)
	var valid=not hit.is_empty() and hit.normal.y>0.65
	if valid:
		point=hit.position+Vector3(0,0.04,0)

		# Test a soldier-sized capsule standing at the floor (centre 0.93 m up).
		var shape_query=PhysicsShapeQueryParameters3D.new()
		shape_query.shape=probe
		shape_query.transform=Transform3D(Basis.IDENTITY,point+Vector3(0,0.93,0))
		shape_query.collision_mask=1
		for obstacle in space.intersect_shape(shape_query,12):
			# Soldiers can open a door along a planned route.
			if obstacle.collider.get_parent().is_in_group("field_door") and not obstacle.collider.get_parent().opened:continue
			valid=false
			break
	var id=id_for(cell)
	if graph.has_point(id):graph.set_point_position(id,point)
	else:graph.add_point(id,point)
	graph.set_point_disabled(id,not valid)

## Re-evaluates all eight connections from `cell`: adds edges that are now
## allowed and removes edges that no longer are.
## Rules: both ends enabled; floor height difference under 0.85 m; diagonals
## also need both orthogonal neighbours open (no squeezing through corners);
## a ray at 0.65 m height between the points must be clear.
func link(cell: Vector2i):
	var source=id_for(cell)
	for dx in range(-1,2):
		for dz in range(-1,2):
			if dx==0 and dz==0:continue
			var neighbour=cell+Vector2i(dx,dz)
			if not inside(neighbour):continue
			var destination=id_for(neighbour)
			var allowed=not graph.is_point_disabled(source) and not graph.is_point_disabled(destination)
			allowed=allowed and absf(graph.get_point_position(source).y-graph.get_point_position(destination).y)<0.85
			if dx!=0 and dz!=0:
				allowed=allowed and not graph.is_point_disabled(id_for(cell+Vector2i(dx,0))) and not graph.is_point_disabled(id_for(cell+Vector2i(0,dz)))
			if allowed:
				var a=graph.get_point_position(source)+Vector3(0,0.65,0)
				var b=graph.get_point_position(destination)+Vector3(0,0.65,0)
				var ray=PhysicsRayQueryParameters3D.create(a,b,1)
				ray.exclude=door_rids
				allowed=get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
			var connected=graph.are_points_connected(source,destination)
			if allowed and not connected:graph.connect_points(source,destination)
			elif not allowed and connected:graph.disconnect_points(source,destination)

## Builds the whole graph once. Waits three physics frames first so colliders
## exist, then samples every cell (yielding every 420 cells to keep frames
## short), then links all cells. Sets ready_for_paths when done.
func build():
	rebuilding=true
	for i in range(3):await get_tree().physics_frame
	update_doors()
	var count=0
	for z in range(MIN_CELL.y,MAX_CELL.y+1):
		for x in range(MIN_CELL.x,MAX_CELL.x+1):
			sample(Vector2i(x,z))
			count+=1
		if count>=420:
			count=0
			await get_tree().physics_frame
	for z in range(MIN_CELL.y,MAX_CELL.y+1):
		for x in range(MIN_CELL.x,MAX_CELL.x+1):link(Vector2i(x,z))
	ready_for_paths=true
	rebuilding=false
	revision+=1

## Collects the RIDs of closed doors so link() rays can pass through them.
func update_doors():
	door_rids.clear()
	for door in get_tree().get_nodes_in_group("field_door"):
		if not door.opened:door_rids.append(door.leaf.get_rid())

## Registers that something changed near `point` (world metres). Called by
## world.gd after destruction, door movement and digging; the actual work is
## deferred 0.15 s to batch nearby changes.
func mark_dirty(point: Vector3):
	dirty[Vector2i(roundi(point.x/STEP),roundi(point.z/STEP))]=true
	cooldown=0.15

## Starts refresh() once changes have settled and no rebuild is running.
## [param delta] physics step in seconds.
func _physics_process(delta):
	# - Parameter delta is fixed at 1/60s (approx 0.01667s) by Engine.max_fps configuration.
	# - Integrates kinematic velocity vectors, applies gravitational acceleration, and updates bounding colliders.
	# - Performs raycast obstacle evaluations before committing spatial position changes.
	cooldown=maxf(0,cooldown-delta)
	if ready_for_paths and not rebuilding and not dirty.is_empty() and cooldown==0:
		refresh()

## Re-samples and re-links only the cells within 6 cells (12 m) of each dirty
## cell, yielding every 240 cells. Cheaper than a full build and keeps the
## graph current for the AI.
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
		if count%240==0:await get_tree().physics_frame
	for cell in cells:link(cell)
	revision+=1
	rebuilding=false

## Returns the walkable floor point closest to `point` (so units snap to real
## ground, including trench floors), or `point` itself before the graph exists.
func floor_point(point: Vector3) -> Vector3:
	if not ready_for_paths:return point
	var id=graph.get_closest_point(point)
	return graph.get_point_position(id) if id>=0 else point

## Returns the A* path as world points from the graph point nearest `start` to
## the one nearest `destination`; empty when not ready or no path exists.
## The third argument to get_point_path (false) disallows partial paths.
func path_between(start: Vector3, destination: Vector3) -> PackedVector3Array:
	if not ready_for_paths:return PackedVector3Array()
	var a=graph.get_closest_point(start)
	var b=graph.get_closest_point(destination)
	if a<0 or b<0:return PackedVector3Array()
	return graph.get_point_path(a,b,false)

## True if a straight ray at `height` (default 1.25 m, chest height) from
## `start` to `destination` hits no static geometry: used for line-of-sight
## style checks such as whether a soldier can walk or shoot directly.
func line_clear(start: Vector3, destination: Vector3, height: float=1.25) -> bool:
	var ray=PhysicsRayQueryParameters3D.create(start+Vector3(0,height,0),destination+Vector3(0,height,0),1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
