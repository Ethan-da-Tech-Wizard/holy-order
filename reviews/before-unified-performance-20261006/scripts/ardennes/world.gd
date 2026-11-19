## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/ardennes/world.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## The Ardennes battlefield: procedural snowy terrain with a winding road,
## ridges with eight German gun positions, pine trees, rocks, craters, cover
## points, a navigation grid and live terrain deformation.
##
## Role: created by battle.gd (which sets `game`). Everything is generated from
## fixed seeds (19441223, the date of the Ardennes offensive) so the map is
## identical every run. Other scripts call road_x / road_point / on_ground /
## surface_height for positions, path_between for navigation, cover_candidates
## for AI cover, blast / dig / carve_ground / deform_ground for destruction, and
## geometry_updated when anything changes.
## Coordinates: the road runs along Z; road distance `progress` counts down from
## ROAD_START (z = 420) toward negative Z. The playable box is LIMIT metres
## half-width by half-length. The eight AREAS are the German hilltops, listed
## from the first ambush hills (left/right of the road) to the last road guns.
## Terrain: 24 x 24 m chunks, each a 6 x 6 grid of 4 m cells built as two
## triangles each; chunks are Prop bodies (kind "soil"), so shells can dig them.
extends Node3D

const Art=preload("res://scripts/art.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")
const Prop=preload("res://scripts/ardennes/prop.gd")
const LIMIT=Vector2(174,426)
const STEP=2.0
const ROAD_START=420.0
const AREAS=[Vector2(-48,180),Vector2(51,167),Vector2(-57,48),Vector2(58,35),Vector2(-53,-79),Vector2(55,-92),Vector2(-51,-207),Vector2(53,-218)]

## Memoised terrain heights keyed by (x, z) once terrain is built.
var height_cache:Dictionary={}

## Turned on after the craters are placed, because earlier queries would cache pre-crater heights.
var height_cache_enabled:bool=false

## The battle controller.
var game

## Simplex noise for hill shapes.
var noise=FastNoiseLite.new()

## All ground bodies.
var terrain_chunks: Array=[]

## Chunk origin (Vector2i) -> chunk body, used by carve_ground.
var terrain_lookup:Dictionary={}

## Recent path results (cleared when geometry changes; capped at 256).
var path_cache:Dictionary={}

## area id -> {position, kind, operator} for the extra MG42 positions.
var secondary_nests:Dictionary={}

## Cache cleared when geometry changes; reserved for height queries on the nav grid.
var navigation_heights:Dictionary={}

## All cover points (rocks, sandbags, logs...).
var covers: Array[Vector3]=[]

## {p, r, node} circles blocking the navigation grid (rocks, wrecks, logs).
var obstacles: Array=[]

## {p, r, d}: shell craters (position, radius, depth) carved into the height function.
var craters: Array=[]

## The eight main machine-gun nests: {position, kind, operator}.
var nests: Array=[]

## Ground position of each area (used as squad anchors and objectives).
var anchors: Array[Vector3]=[]

## AStarGrid2D over the road and ridges.
var navigation: AStarGrid2D

## Counter bumped by geometry_updated(); AI compares it to detect stale cover and paths.
var geometry_revision:int=0

## Last 32 changes {revision, point} for cover_changed().
var geometry_changes:Array=[]

## Queue of terrain/prop cuts waiting for their turn (max 96).
var pending_cuts:Array=[]

## Bodies currently rebuilding after a cut.
var active_cuts:Array=[]

## Count of cuts executed (statistic).
var cut_jobs:int=0

## Chunk origin -> 25 x 25 height array of edited chunks (see deform_ground).
var soil_edits:Dictionary={}

## Camera used on the title screen.
var world_camera:Camera3D

## Snow/dirt shader material: mixes dark dirt on steep faces with icy snow, with a road strip and noise grain.
var snow:ShaderMaterial

## Seeded random generator for scenery.
var rng=RandomNumberGenerator.new()

## Seed of the scenery random generator.
var rng_seed:int=19441223

## Number of ground chunks built.
var terrain_meshes:int=0

## 20 m grid of cover points for fast lookups.
var cover_grid:Dictionary={}

## Pine mesh variants shared by all trees.
static var pine_cache:Dictionary={}

## The WorldEnvironment node.
var ambient:WorldEnvironment

## Godot lifecycle hook: builds the terrain and everything on it, in dependency order.
## Order: noise and snow shader, craters (34 random + 5 around each area), terrain chunks over
## -96..96 x -456..456, lighting, 140 pines and 38 rocks (kept out of the road corridor
## and fire lanes and 15 m clear of the areas), nests, cover grid, navigation grid and the title camera.
func _ready():
	add_to_group("battle_world")
	rng.seed=rng_seed
	noise.seed=19441223
	noise.frequency=0.007
	noise.noise_type=FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var shader=Shader.new()

	# Inline shader (spatial, cull_back): blends dirt and ice by surface slope and
	# distance from the road centre line, so the road is trampled and the ridges
	# are snow-covered. Its road formula repeats road_x() on the GPU.
	shader.code="""shader_type spatial;
render_mode cull_back;
varying vec3 wp;
varying vec3 wn;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wn=normalize(MODEL_NORMAL_MATRIX*NORMAL);}
float hash(vec3 p){return fract(sin(dot(floor(p),vec3(12.9898,78.233,36.31)))*43758.5453);}
void fragment(){
float road=sin(wp.z*0.017)*13.0+sin(wp.z*0.044)*3.0;
float lane=1.0-smoothstep(4.8,7.2,abs(wp.x-road));
float grain=hash(wp*9.0)*0.075+hash(wp*1.9)*0.04;
float face=smoothstep(0.68,0.95,wn.y);
vec3 dirt=vec3(0.18,0.16,0.135)+grain*0.6;
vec3 ice=vec3(0.63,0.70,0.73)+grain;
ALBEDO=mix(dirt,ice,face*(1.0-lane*0.84)); ROUGHNESS=0.95;
}"""
	snow=ShaderMaterial.new()
	snow.shader=shader
	for i in range(34):
		var p=Vector3(rng.randf_range(-155,155),0,rng.randf_range(-310,365))
		if absf(p.x-road_x(p.z))<10: p.x+=22
		craters.append({"p":p,"r":rng.randf_range(3.5,7.3),"d":rng.randf_range(0.45,1.05)})
	for entry in AREAS:
		anchors.append(on_ground(Vector3(entry.x,0,entry.y)))
		craters.append({"p":Vector3(entry.x,0,entry.y),"r":5.0,"d":0.35})
		for j in [-2,-1,1,2]:
			craters.append({"p":Vector3(entry.x+j*3.0,0,entry.y-3.5),"r":4.2,"d":0.6})
	height_cache_enabled=true
	for x in range(-192,192,24):
		for z in range(-456,456,24):
			ground_chunk(x,z)
	build_lighting()
	for i in range(510):
		var p=Vector3(rng.randf_range(-174,174),0,rng.randf_range(-415,418))
		if absf(p.x-road_x(p.z))<10 or in_fire_lane(p):continue
		var clear=true
		for a in anchors:
			if Vector2(p.x-a.x,p.z-a.z).length()<15:clear=false
		if clear:tree(on_ground(p),rng.randf_range(8.0,17.0),i%5)
	for i in range(100):
		var p=Vector3(rng.randf_range(-166,166),0,rng.randf_range(-360,360))
		if absf(p.x-road_x(p.z))<10 or in_fire_lane(p):continue
		rock(on_ground(p),rng.randf_range(0.8,2.4))
	for i in range(8):
		build_nest(i)
	for i in range(4):build_secondary_nest(i)
	for p in covers:
		var key=Vector2i(floori(p.x/20),floori(p.z/20))
		if not cover_grid.has(key):cover_grid[key]=[]
		cover_grid[key].append(p)
	build_navigation()
	world_camera=Camera3D.new()
	add_child(world_camera)
	world_camera.position=on_ground(Vector3(-48,0,225))+Vector3(0,10,0)
	world_camera.look_at(on_ground(Vector3(-21,0,146))+Vector3(0,1,0))
	world_camera.far=650
	world_camera.fov=63

## X coordinate of the road centre line at world z: two sine waves (periods about 370 m and 143 m) giving a gentle winding road with amplitude 13 m and 3 m.
func road_x(z:float)->float:
	return sin(z*0.017)*13.0+sin(z*0.044)*3.0

## Un-edited terrain height. Between the road shoulders (9 m) and 44 m from the centre, height blends from a flat road bed (with a very gentle swell) into noisy hills
## plus a 9.5 m Gaussian bump under each German area, which creates the ridges.
func raw_height(x:float,z:float)->float:
	# Broad ridges with a low-amplitude surface. Road shoulders and firing lanes
	# are graded approaches, not the old high-frequency walls of noise.
	var lane=sin(z*0.013)*1.3
	var hill=noise.get_noise_2d(x,z)*3.8+1.5*sin(z*0.012)
	for area in AREAS:
		var d=Vector2((x-area.x)/39.0,(z-area.y)/43.0)
		hill+=9.5*exp(-d.length_squared())
	var off=absf(x-road_x(z))
	return lerpf(lane,hill,smoothstep(9.0,44.0,off))

## True if `p` is within 7 m of the straight line from an area to the road: nothing is planted there so the guns have a view.
func in_fire_lane(p:Vector3)->bool:
	for area in AREAS:
		var a=Vector2(area.x,area.y)
		var b=Vector2(road_x(area.y),area.y+5)
		var q=Vector2(p.x,p.z)
		var t=clampf((q-a).dot(b-a)/(b-a).length_squared(),0,1)
		if q.distance_squared_to(a+(b-a)*t)<49:return true
	return false

## Final terrain height: raw height, flattened near each area into a platform (blend 8 to 24 m), then shell craters (a bowl with a raised rim).
func height_at(x:float,z:float)->float:
	var key=Vector2(x,z)
	if height_cache_enabled and height_cache.has(key):return height_cache[key]
	var h=raw_height(x,z)
	# Constructed firing positions sit on prepared platforms, not arbitrary slopes.
	for area in AREAS:
		var distance=Vector2(x-area.x,z-area.y).length()
		if distance<24:h=lerpf(raw_height(area.x,area.y),h,smoothstep(8,24,distance))
	for c in craters:
		var d=Vector2(x-c.p.x,z-c.p.z).length()/c.r
		if d<1.4:
			h-=c.d*(1.0-smoothstep(0.20,1.0,d))
			h+=0.20*exp(-pow((d-1.02)*7.0,2.0))
	if height_cache_enabled:height_cache[key]=h
	return h

## Returns `p` with y set to the surface height at its x, z.
func on_ground(p:Vector3)->Vector3:
	return Vector3(p.x,surface_height(p.x,p.z),p.z)

## World position on the road centre line at distance `progress` along the road.
func road_point(progress:float)->Vector3:
	var z=ROAD_START-progress
	return on_ground(Vector3(road_x(z),0,z))

## Builds one 24 x 24 m ground chunk at (x, z): a Prop in kind "soil", the triangle mesh from height_at, and a trimesh collider.
func ground_chunk(x:float,z:float):
	var body=Prop.new()
	body.material_kind="soil"
	body.battle_world=self
	body.position=Vector3(x,0,z)
	add_child(body)
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for ix in range(6):
		for iz in range(6):
			var a=Vector3(ix*4,height_at(x+ix*4,z+iz*4),iz*4)
			var b=Vector3((ix+1)*4,height_at(x+(ix+1)*4,z+iz*4),iz*4)
			var c=Vector3((ix+1)*4,height_at(x+(ix+1)*4,z+(iz+1)*4),(iz+1)*4)
			var d=Vector3(ix*4,height_at(x+ix*4,z+(iz+1)*4),(iz+1)*4)
			tri(st,a,c,b)
			tri(st,a,d,c)
	st.generate_normals()
	var mesh=st.commit()
	Art.mesh(body,mesh,Vector3.ZERO,snow)
	var collision=CollisionShape3D.new()
	collision.shape=mesh.create_trimesh_shape()
	body.add_child(collision)
	terrain_chunks.append(body)
	terrain_lookup[Vector2i(int(x),int(z))]=body
	terrain_meshes+=1

## Adds a triangle to a SurfaceTool with the winding that faces up.
func tri(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3):
	for v in [a,c,b]:st.add_vertex(v)

## Creates a destructible box prop with a bevelled visual and box collider.
## [param size] metres, [param p] position, [param mat] material, [param kind] damage material kind, [param parent] node to attach to.
func solid(size:Vector3,p:Vector3,mat:Material,kind:String="wood",parent:Node3D=self):
	var body=Prop.new()
	body.material_kind=kind
	body.battle_world=self
	parent.add_child(body)
	body.position=p
	body.set_meta("solid_size",size)
	Art.beveled_box(body,size,Vector3.ZERO,mat,minf(0.05,size.x*0.1))
	var cs=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=size
	cs.shape=box
	body.add_child(cs)
	return body

## Creates a pine: a trunk collider and a shared baked canopy mesh that fades out beyond 270 m; trunks with health 260 + 12 per metre of height, so a tree falls after taking enough damage.
func tree(p:Vector3,height:float,variant:int):
	var tree_root=Prop.new()
	tree_root.battle_world=self
	tree_root.material_kind="wood"
	tree_root.is_tree=true
	tree_root.tree_health=260+height*12
	add_child(tree_root)
	tree_root.position=p
	var r=0.26+height*0.012
	Art.cylinder(tree_root,r,height,Vector3(0,height*0.5,0),Art.material(Color("3b342e")),r*0.48,8)
	var cs=CollisionShape3D.new()
	var cylinder=CylinderShape3D.new()
	cylinder.radius=r
	cylinder.height=height
	cs.shape=cylinder
	cs.position.y=height*0.5
	tree_root.add_child(cs)
	var canopy=Node3D.new()
	canopy.add_to_group("inventory_visual")
	tree_root.add_child(canopy)
	if not pine_cache.has(variant):pine_cache[variant]=pine_mesh(variant)
	var visual=MeshInstance3D.new()
	visual.mesh=pine_cache[variant]
	visual.visibility_range_end=270
	visual.visibility_range_end_margin=25
	visual.visibility_range_fade_mode=GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	visual.scale=Vector3.ONE*height
	canopy.add_child(visual)
	obstacles.append({"p":p,"r":r+0.5,"node":tree_root})
	for v in [Vector3(1.4,0,0),Vector3(-1.4,0,0),Vector3(0,0,1.4),Vector3(0,0,-1.4)]:covers.append(on_ground(p+v))

## Creates a boulder (a squashed sphere with a convex collider), registers it as a navigation obstacle and adds four cover points around it.
func rock(p:Vector3,radius:float):
	var body=Prop.new()
	body.material_kind="rock"
	body.battle_world=self
	add_child(body)
	body.position=p
	var shape=SphereMesh.new()
	shape.radius=radius
	shape.height=radius*1.45
	shape.radial_segments=10
	shape.rings=5
	var mesh=Art.mesh(body,shape,Vector3(0,radius*0.4,0),snow)
	mesh.rotation.y=rng.randf()*TAU
	var cs=CollisionShape3D.new()
	cs.shape=shape.create_convex_shape()
	cs.position.y=radius*0.4
	body.add_child(cs)
	obstacles.append({"p":p,"r":radius+0.4,"node":body})
	for j in range(4):covers.append(on_ground(p+Vector3(cos(j*PI/2),0,sin(j*PI/2))*(radius+1.1)))

## Builds German position `index`: a line of three sandbag walls facing the road, an MG platform and trench, rear shelter, and cover points. Registers it in `nests`.
func build_nest(index:int):
	var p=on_ground(anchors[index])
	anchors[index]=p
	var facing=(Vector3(road_x(p.z),p.y,p.z+15)-p).normalized()
	var right=facing.cross(Vector3.UP)
	var bag=Art.material(Color("8f9080"))
	for dx in [-2.5,0,2.5]:
		var part=solid(Vector3(2.3,0.90,0.65),p+facing*2.1+right*dx+Vector3(0,0.43,0),bag,"sandbag")
		part.rotation.y=atan2(facing.x,facing.z)
		part.get_child(0).queue_free()
		var bags=Node3D.new()
		for row in range(3):
			for column in range(3):
				Art.beveled_box(bags,Vector3(0.76,0.28,0.66),Vector3((column-1)*0.74+(0.08 if row%2 else 0),row*0.28-0.26,0),bag,0.075)
		var bags_mesh=MeshInstance3D.new()
		bags_mesh.mesh=Kit.bake(bags)
		part.add_child(bags_mesh)
		bags.free()
		obstacles.append({"p":part.position,"r":1.1,"node":part})
		for j in [-0.7,0,0.7]:
			Art.box(part,Vector3(0.025,0.018,0.66),Vector3(j,0.30,0),Art.material(Color("57594b")))
	for side in [-1,1]:
		var wing=solid(Vector3(0.70,0.95,3.2),p+right*side*3.2+Vector3(0,0.40,0),bag,"sandbag")
		wing.rotation.y=atan2(facing.x,facing.z)
	for d in [-1.4,0,1.4]:covers.append(on_ground(p+right*d))
	var mount=solid(Vector3(0.22,0.8,0.22),p+Vector3(0,0.55,0),Art.material(Color("424942")),"metal")
	for offset in [Vector3(-0.7,-0.3,0.5),Vector3(0.7,-0.3,0.5),Vector3(0,-0.3,-0.7)]:
		Art.segment(mount,Vector3(0,0.3,0),offset,0.035,Art.material(Color("424942")))
	nests.append({"position":p,"mount":mount,"kind":"mg34" if index%3==0 else "mg42","operator":null})
	var crate=solid(Vector3(0.65,0.44,0.45),p+right*1.1+Vector3(0,0.2,0),Art.material(Color("5c603f")))
	crate.set_meta("ammo_crate",index)
	var timber=Art.material(Color("544b3c"))
	# Rear shelter and a traversed communication trench connect to the MG platform.
	var rear=on_ground(p-facing*6.5)
	for side in [-1,1]:
		var wall=solid(Vector3(0.28,1.65,3.2),rear+right*side*2.0+Vector3(0,0.65,0),timber)
		wall.rotation.y=atan2(facing.x,facing.z)
	var roof=solid(Vector3(4.3,0.27,3.4),rear+Vector3(0,1.62,0),timber)
	roof.rotation.y=atan2(facing.x,facing.z)
	Art.box(roof,Vector3(4.2,0.045,3.3),Vector3(0,0.157,0),Art.material(Color("aebcbd")))
	for j in [-2,-1,0,1,2]:
		var revet=on_ground(p+right*j*3.0-facing*3.5)
		var plank=solid(Vector3(2.8,0.75,0.16),revet-facing*1.0+Vector3(0,0.25,0),timber)
		plank.rotation.y=atan2(facing.x,facing.z)
		covers.append(on_ground(revet))
	for offset in [-6.5,6.5]:
		var flank=on_ground(p+right*offset-facing*1.5)
		solid(Vector3(1.4,0.85,0.55),flank+Vector3(0,0.40,0),bag,"sandbag").rotation.y=atan2(facing.x,facing.z)
		covers.append(flank-facing*0.9)

## Creates the environment (procedural sky, filmic tone mapping, low-lying fog with a height falloff, ambient light) and the low winter sun with shadows to 95 m.
func build_lighting():
	ambient=WorldEnvironment.new()
	var env=Environment.new()
	env.background_mode=Environment.BG_SKY
	var sky=Sky.new()
	var sky_mat=ProceduralSkyMaterial.new()
	sky_mat.sky_top_color=Color("526982")
	sky_mat.sky_horizon_color=Color("bdc9cd")
	sky_mat.ground_horizon_color=Color("a6b8bd")
	sky_mat.ground_bottom_color=Color("5b686d")
	sky.sky_material=sky_mat
	env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("b4c7d5")
	env.ambient_light_energy=0.30
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure=1.10
	env.fog_enabled=true
	env.fog_light_color=Color("9cabb5")
	env.fog_density=0.0020
	env.fog_height=7
	env.fog_height_density=0.018
	env.ssao_enabled=true
	env.ssao_radius=0.8
	env.ssao_intensity=1.1
	ambient.environment=env
	add_child(ambient)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-24,-32,0)
	sun.light_color=Color("eee1c3")
	sun.light_energy=1.3
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=95
	add_child(sun)

## Creates the AStarGrid2D over the region (-45, -213, 91, 427 cells = 182 x 854 m): marks cells near obstacles solid and makes crater cells cost 1.7x so soldiers avoid them.
func build_navigation():
	navigation=AStarGrid2D.new()
	navigation.region=Rect2i(-87,-213,175,427)
	navigation.cell_size=Vector2(STEP,STEP)
	navigation.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	navigation.default_compute_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	navigation.default_estimate_heuristic=AStarGrid2D.HEURISTIC_OCTILE
	navigation.update()
	for o in obstacles:
		var c=cell(o.p)
		for dx in range(-2,3):
			for dz in range(-2,3):
				var v=c+Vector2i(dx,dz)
				if navigation.is_in_boundsv(v) and Vector2(v.x*STEP-o.p.x,v.y*STEP-o.p.z).length()<o.r+0.9:navigation.set_point_solid(v,true)
	for c in craters:
		var v=cell(c.p)
		if navigation.is_in_boundsv(v):navigation.set_point_weight_scale(v,1.7)

## World position to grid cell (rounded).
func cell(p:Vector3)->Vector2i:
	return Vector2i(roundi(p.x/STEP),roundi(p.z/STEP))

## Nearest free grid cell to `p`, searching up to 4 cells away if its own cell is solid.
func nearest_cell(p:Vector3)->Vector2i:
	var c=cell(p).clamp(navigation.region.position,navigation.region.end-Vector2i.ONE)
	if not navigation.is_point_solid(c):return c
	for radius in range(1,5):
		for dx in range(-radius,radius+1):
			for dz in range(-radius,radius+1):
				var v=c+Vector2i(dx,dz)
				if navigation.is_in_boundsv(v) and not navigation.is_point_solid(v):return v
	return c

## A* path between two world points as a list of corner points: collinear points are dropped and the destination is appended. Returns an empty array if either end is blocked. Results are cached (256 entries); heights are left zero as characters follow the ground physically.
func path_between(a:Vector3,b:Vector3)->PackedVector3Array:
	var from=nearest_cell(a)
	var to=nearest_cell(b)
	var key=Vector4i(from.x,from.y,to.x,to.y)
	if path_cache.has(key):return path_cache[key]
	var result=PackedVector3Array()
	if navigation.is_point_solid(from) or navigation.is_point_solid(to):return result
	var route=navigation.get_id_path(from,to)
	# Height isn't needed on every path point: CharacterBody follows collision.
	# Keep direction-changing corners, reducing per-soldier waypoint work.
	for i in range(route.size()):
		if i>0 and i<route.size()-1 and route[i]-route[i-1]==route[i+1]-route[i]:continue
		var p=route[i]
		result.append(Vector3(p.x*STEP,0,p.y*STEP))
	if not result.is_empty():result.append(b)
	if path_cache.size()>256:path_cache.clear()
	path_cache[key]=result
	return result

## Marks that the world changed near `point`: bumps the revision, clears caches and re-evaluates the 5 x 5 navigation cells around it against live obstacles within 18 m.
func geometry_updated(point:Vector3):
	geometry_revision+=1
	path_cache.clear()
	navigation_heights.clear()
	geometry_changes.append({"revision":geometry_revision,"point":point})
	if geometry_changes.size()>32:geometry_changes.pop_front()
	if navigation==null:return
	var c=cell(point)
	var nearby:Array=[]
	for obstacle in obstacles:
		if is_instance_valid(obstacle.node) and not obstacle.node.destroyed and Vector2(point.x-obstacle.p.x,point.z-obstacle.p.z).length_squared()<324:nearby.append(obstacle)
	for dx in range(-2,3):
		for dz in range(-2,3):
			var v=c+Vector2i(dx,dz)
			if not navigation.is_in_boundsv(v):continue
			var p=Vector3(v.x*STEP,height_at(v.x*STEP,v.y*STEP),v.y*STEP)
			var blocked=false
			for o in nearby:
				if Vector2(p.x-o.p.x,p.z-o.p.z).length_squared()<pow(o.r+0.7,2):
					blocked=true
					break
			navigation.set_point_solid(v,blocked)

## True if cover chosen at revision `since` may now be invalid: more than 32 revisions old, or a change within 10 m after it.
func cover_changed(point:Vector3,since:int)->bool:
	if geometry_revision-since>32:return true
	for change in geometry_changes:
		if change.revision>since and change.point.distance_squared_to(point)<100:return true
	return false

## Queues a carve request instead of running it now, merging a request within 0.5 m on the same body (radius = max) and refusing more than 96 queued.
## [param body] the Prop to cut. [param point] world position. [param radius] hole radius.
func queue_cut(body,point:Vector3,radius:float):
	# Limit geometry work, coalesce close hits and keep the queue bounded under MG fire.
	for cut in pending_cuts:
		if cut.body==body and cut.local.distance_squared_to(body.to_local(point))<0.25:
			cut.radius=maxf(cut.radius,radius)
			return
	if pending_cuts.size()<96:pending_cuts.append({"body":body,"local":body.to_local(point),"radius":radius})

## Runs at most one queued cut at a time with a 0.08 s gap, only when no previous cut is still rebuilding: this prevents a burst of fire from stalling the game with many CSG operations.
func _process(_delta):
	for body in active_cuts.duplicate():
		if not is_instance_valid(body) or not body.rebuilding:active_cuts.erase(body)
	if active_cuts.size()>=1 or pending_cuts.is_empty():return
	var job=pending_cuts.pop_front()
	if is_instance_valid(job.body) and not job.body.destroyed:
		job.body.commit_cut(job.body.to_global(job.local),job.radius)
		active_cuts.append(job.body)
		cut_jobs+=1

## Applies an explosion: shallow crater in the soil if within 1.4 m of the ground, then damage_at to every non-soil breakable within `radius` (with falloff) and a 1.25 m cut size.
## [param power] damage. [param radius] metres. [param soil_radius] crater radius. [param soil_depth] crater depth.
func blast(point:Vector3,power:float=340,radius:float=5.0,soil_radius:float=0.7,soil_depth:float=0.13):
	# Fragmentation radius is separate from excavation. A grenade makes a shallow
	# scar in soil, while close hits can still breach timber and thin walls.
	var surface=surface_height(point.x,point.z)
	if point.y-surface<1.4:
		carve_ground(Vector3(point.x,surface+soil_radius-soil_depth,point.z),soil_radius)
	for body in get_tree().get_nodes_in_group("breakable"):
		if body.destroyed or body.material_kind=="soil":continue
		if body.global_position.distance_squared_to(point)>pow(radius+18,2):continue
		var distance=body.distance_to_surface(point)
		if distance>radius:continue
		body.damage_at(power*(1.0-distance/(radius+1.0)),point,1.25,true)

## Lowers the terrain inside a sphere by asking every 24 m chunk the sphere touches to carve.
func carve_ground(center:Vector3,radius:float):
	var first=Vector2i(floori((center.x-radius)/24)*24,floori((center.z-radius)/24)*24)
	var last=Vector2i(floori((center.x+radius)/24)*24,floori((center.z+radius)/24)*24)
	for x in range(first.x,last.x+1,24):
		for z in range(first.y,last.y+1,24):
			var body=terrain_lookup.get(Vector2i(x,z))
			if body!=null:body.carve(center,radius)

## Shovel dig: carve_ground with a sphere centred so that it cuts `depth` m (default 0.42) into the surface.
func dig(point:Vector3,width:float=1.0,depth:float=0.42):
	var ground=surface_height(point.x,point.z)
	carve_ground(Vector3(point.x,ground+width-depth,point.z),width)

## There are no doors here; always null (keeps the interface shared with the desert world).
func nearby_door(_point:Vector3,_distance:float=2.6):return null

## Topples a tree: disables its collision, tips it over in 1.7 s, leaves a 6.5 m log with collision as new cover and an obstacle.
func fell_tree(body):
	if body.destroyed:return
	var origin=body.global_position
	body.destroyed=true
	body.collision_layer=0
	var tween=create_tween()
	tween.tween_property(body,"rotation:z",PI/2*signf(randf()-0.5),1.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	geometry_updated(origin)
	var log_body=solid(Vector3(6.5,0.6,0.7),origin+Vector3(2.8,0.27,0),Art.material(Color("494038")),"wood")
	obstacles.append({"p":log_body.position,"r":2.4,"node":log_body})
	covers.append(on_ground(origin+Vector3(3,0,1.1)))
	geometry_updated(log_body.position)

## Up to 16 cover points within `radius` of `p`, nearest first, found through the 20 m grid.
func cover_candidates(p:Vector3,radius:float)->Array:
	var key=Vector2i(floori(p.x/20),floori(p.z/20))
	var candidates:Array=[]
	for x in range(-2,3):
		for z in range(-2,3):
			for point in cover_grid.get(key+Vector2i(x,z),[]):
				if point.distance_squared_to(p)<radius*radius:candidates.append(point)
	candidates.sort_custom(func(a,b):return a.distance_squared_to(p)<b.distance_squared_to(p))
	return candidates.slice(0,16)

## Generates a pine canopy mesh: 16 layers of 10 drooping branches (each four triangles) with vertex colours in dark green and occasional snow patches; variant selects the random seed.
func pine_mesh(variant:int)->ArrayMesh:
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var prng=RandomNumberGenerator.new()
	prng.seed=91+variant
	for layer in range(16):
		var y=0.22+layer*0.047
		var radius=(1.0-y)*0.30
		for spoke in range(10):
			var angle=spoke*TAU/10+layer*0.47
			var direction=Vector3(cos(angle),0,sin(angle))
			var side=direction.cross(Vector3.UP)
			var tip=Vector3(0,y,0)+direction*radius*prng.randf_range(0.88,1.12)
			var center=Vector3(0,y+0.015,0)+direction*radius*0.46
			var a=center-side*radius*0.30
			var b=center+side*radius*0.30
			var inner=Vector3(0,y+0.08,0)
			var color=Color("273e35").lightened(prng.randf_range(0,0.075))
			for triangle in [[inner,a,tip],[inner,tip,b],[a,center-Vector3(0,0.016,0),tip],[b,tip,center-Vector3(0,0.016,0)]]:
				for point in triangle:
					st.set_color(color.srgb_to_linear())
					st.add_vertex(point)
			if prng.randf()<0.62:
				for point in [inner.lerp(center,0.3)+Vector3(0,0.004,0),a.lerp(center,0.3)+Vector3(0,0.004,0),tip.lerp(center,0.24)+Vector3(0,0.004,0)]:
					st.set_color(Color("aebcbd").srgb_to_linear())
					st.add_vertex(point)
	st.generate_normals()
	var material=Kit.vertex_material().duplicate()
	material.cull_mode=BaseMaterial3D.CULL_DISABLED
	st.set_material(material)
	return st.commit()

## Terrain height at (x, z) interpolated over the same two triangles the mesh uses (the 4 m cell split on its diagonal), so actors never sink beneath a triangle.
func base_surface_height(x:float,z:float)->float:
	# Spawn and path heights match the actual two triangles of the 4 m terrain cell.
	# Sampling the unsimplified noise could place an actor underneath a triangle.
	var gx=floorf(x/4)*4
	var gz=floorf(z/4)*4
	var u=(x-gx)/4
	var v=(z-gz)/4
	var a=height_at(gx,gz)
	var b=height_at(gx+4,gz)
	var c=height_at(gx+4,gz+4)
	var d=height_at(gx,gz+4)
	if u>=v:return a+(b-a)*u+(c-b)*v
	return a+(c-d)*u+(d-a)*v

## Terrain height including shell and shovel edits: uses the stored per-vertex heights of an edited chunk (same triangle interpolation) or falls back to base_surface_height.
func surface_height(x:float,z:float)->float:
	var key=Vector2i(floori(x/24)*24,floori(z/24)*24)
	if not soil_edits.has(key):return base_surface_height(x,z)
	var gx=clampi(floori(x-key.x),0,23)
	var gz=clampi(floori(z-key.y),0,23)
	var u=x-key.x-gx
	var v=z-key.y-gz
	var h:PackedFloat32Array=soil_edits[key]
	var a=h[gx*25+gz]
	var b=h[(gx+1)*25+gz]
	var c=h[(gx+1)*25+gz+1]
	var d=h[gx*25+gz+1]
	return a+(b-a)*u+(c-b)*v if u>=v else a+(c-d)*u+(d-a)*v

## Lowers the terrain of one chunk to the bottom of a sphere: stores one height per vertex (25 x 25 per chunk) instead of replaying every earlier edit, rebuilds the mesh and trimesh collider, and calls geometry_updated.
## [param body] the chunk. [param point] sphere centre. [param radius] sphere radius.
func deform_ground(body,point:Vector3,radius:float):
	# Store one height per vertex, rather than replaying every previous explosion
	# and shovel stroke on every future edit or navigation query.
	var key=Vector2i(roundi(body.position.x),roundi(body.position.z))
	var heights:PackedFloat32Array
	if soil_edits.has(key):heights=soil_edits[key]
	else:
		heights.resize(625)
		for x in range(25):
			for z in range(25):heights[x*25+z]=base_surface_height(key.x+x,key.y+z)
	var changed=false
	for x in range(maxi(0,floori(point.x-radius-key.x)),mini(24,ceili(point.x+radius-key.x))+1):
		for z in range(maxi(0,floori(point.z-radius-key.y)),mini(24,ceili(point.z+radius-key.y))+1):
			var distance=Vector2(key.x+x-point.x,key.y+z-point.z).length_squared()
			if distance>=radius*radius:continue
			var lowered=maxf(-40,point.y-sqrt(radius*radius-distance))
			if lowered<heights[x*25+z]-0.002:
				heights[x*25+z]=lowered
				changed=true
	if not changed:return
	soil_edits[key]=heights
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for x in range(24):
		for z in range(24):
			var a=Vector3(x,heights[x*25+z],z)
			var b=Vector3(x+1,heights[(x+1)*25+z],z)
			var c=Vector3(x+1,heights[(x+1)*25+z+1],z+1)
			var d=Vector3(x,heights[x*25+z+1],z+1)
			tri(st,a,c,b)
			tri(st,a,d,c)
	st.generate_normals()
	st.index()
	var mesh=st.commit()
	for child in body.get_children():
		if child is CollisionShape3D:child.shape=mesh.create_trimesh_shape()
	for old in body.owned_meshes():
		old.hide()
		old.queue_free()
	Art.mesh(body,mesh,Vector3.ZERO,snow)
	body.cuts_completed+=1
	body.bounds_valid=false
	geometry_updated(point)

## Adds an extra MG42 sandbag position to the right of area `area`'s main nest and a cover point.
func build_secondary_nest(area:int):
	var center=anchors[area]
	var facing=(Vector3(road_x(center.z),center.y,center.z+5)-center).normalized()
	var side=facing.cross(Vector3.UP)
	var p=on_ground(center+side*10-facing*2)
	var bag=Art.material(Color("858878"))
	for offset in [-0.8,0.8]:
		var wall=solid(Vector3(1.5,0.8,0.65),p+facing*1.8+side*offset+Vector3(0,0.4,0),bag,"sandbag")
		wall.rotation.y=atan2(facing.x,facing.z)
	secondary_nests[area]={"position":p,"kind":"mg42","operator":null}
	covers.append(p)
