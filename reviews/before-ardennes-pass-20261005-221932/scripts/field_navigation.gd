extends Node3D

# A small tactical ground graph, refreshed locally when a door moves or geometry
# changes. It is sampled from live collision, including the floors of dug trenches.
const MIN_CELL=Vector2i(-35,-44)
const MAX_CELL=Vector2i(35,30)
const WIDTH=71
const STEP=2.0
var graph=AStar3D.new()
var ready_for_paths: bool=false
var rebuilding: bool=false
var dirty: Dictionary={}
var cooldown: float=0
var probe: CapsuleShape3D
var revision: int=0
var door_rids: Array[RID]=[]

func _ready():
	probe=CapsuleShape3D.new()
	probe.radius=0.36
	probe.height=1.82
	call_deferred("build")

func id_for(cell: Vector2i) -> int:
	return cell.x-MIN_CELL.x+(cell.y-MIN_CELL.y)*WIDTH

func inside(cell: Vector2i) -> bool:
	return cell.x>=MIN_CELL.x and cell.x<=MAX_CELL.x and cell.y>=MIN_CELL.y and cell.y<=MAX_CELL.y

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

func update_doors():
	door_rids.clear()
	for door in get_tree().get_nodes_in_group("field_door"):
		if not door.opened:door_rids.append(door.leaf.get_rid())

func mark_dirty(point: Vector3):
	dirty[Vector2i(roundi(point.x/STEP),roundi(point.z/STEP))]=true
	cooldown=0.15

func _physics_process(delta):
	cooldown=maxf(0,cooldown-delta)
	if ready_for_paths and not rebuilding and not dirty.is_empty() and cooldown==0:
		refresh()

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

func floor_point(point: Vector3) -> Vector3:
	if not ready_for_paths:return point
	var id=graph.get_closest_point(point)
	return graph.get_point_position(id) if id>=0 else point

func path_between(start: Vector3, destination: Vector3) -> PackedVector3Array:
	if not ready_for_paths:return PackedVector3Array()
	var a=graph.get_closest_point(start)
	var b=graph.get_closest_point(destination)
	if a<0 or b<0:return PackedVector3Array()
	return graph.get_point_path(a,b,false)

func line_clear(start: Vector3, destination: Vector3, height: float=1.25) -> bool:
	var ray=PhysicsRayQueryParameters3D.create(start+Vector3(0,height,0),destination+Vector3(0,height,0),1)
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
