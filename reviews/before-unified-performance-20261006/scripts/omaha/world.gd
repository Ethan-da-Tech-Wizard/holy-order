## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/omaha/world.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## The Omaha Beach battlefield: sea, beach, bluffs with three draws, three
## barbed-wire rows, a sea wall, eight bunkers with trenches, obstacles and mines,
## and a three-by-eight block French village with streets, a church and a
## street navigation grid.
##
## Role: derived from the Ardennes world (ardennes/world.gd), reusing its
## terrain chunking, deformation, cover and navigation API (road_x is replaced by
## the street grid here), but with a different terrain function, a larger map and
## many builders. Created by omaha/battle.gd (sets `game`); all layout numbers
## come from layout.gd. Randomness is seeded with 19440606 (D-Day) so the map is identical on every run.
## Terrain: 48 m tiles (TILE); height in metres comes from raw_height() (beach
## slope, shingle, bluff with three draws, plateau at TOWN_GROUND), then trenches,
## bunker platforms and shell craters in height_at(). Tiles near the fortifications use
## a 2 m grid, elsewhere 4 m (grid_step), and tiles hit by shells refine to 1 m cells.
## Performance: static box visuals are merged into per-material, per-96 m MultiMeshes
## (batch_static_boxes) while their colliders stay; first damage "unbatches" a panel (armor.gd).
extends "res://scripts/ardennes/world.gd"
const Armor=preload("res://scripts/omaha/armor.gd")
const Wire=preload("res://scripts/omaha/wire.gd")
const Layout=preload("res://scripts/omaha/layout.gd")

## Terrain tile size in metres (48).
const TILE:int=48

## Map width from layout.gd.
const WIDTH:float=Layout.WIDTH

## Map depth from layout.gd.
const DEPTH:float=Layout.DEPTH

## z of the three wire rows.
const WIRE_ROWS=Layout.WIRE_ROWS

## All wire segments.
var wires:Array=[]

## Wire segments per row, ordered by x (used to find the segment in a lane).
var wires_by_row:Array=[[],[],[]]

## Breached segments per row; AI paths through these.
var gaps_by_row:Array=[[],[],[]]

## Number of merged box batches (statistic).
var static_batches:int=0

## Bunker records.
var bunkers:Array=[]

## Mined posts {point, live}.
var mines:Array=[]

## Reference points in the village for AI.
var town_points:Array[Vector3]=[]

## Bunker concrete material.
var concrete:StandardMaterial3D

## Stone/masonry material.
var masonry:StandardMaterial3D

## Sea surface mesh.
var sea:MeshInstance3D

## Trench centre lines as pairs of Vector2 (x, z); height_at digs along them.
var trench_segments:Array=[]

## Key -> MultiMeshInstance3D for instanced scenery (hedgehogs, posts, wire, boxes).
var obstacle_batches:Dictionary={}

## Playable half extents in metres: the map minus a margin.
func play_bounds()->Vector2:return Vector2(WIDTH-8,DEPTH-10)

## Godot lifecycle hook: seeds noise and craters, builds trench lines (two cross-beach rows and a trench to each sector), sets up terrain tiles and builds everything in order: coastal light, sea, obstacles, wire, sea wall, bunkers, trench details, village, street navigation, then merges static boxes.
func _ready():
	add_to_group("battle_world")
	rng.seed=19440606
	noise.seed=19440606
	noise.frequency=0.009
	for x in Layout.SECTORS:
		anchors.append(Vector3(x,0,Layout.BUNKER))
	for x in range(-340,340,12):
		for z in Layout.TRENCHES:
			trench_segments.append([Vector2(x,z+sin(x*0.044)*5),Vector2(x+12,z+sin((x+12)*0.044)*5)])
	for x in Layout.SECTORS:
		for z in range(-328,-228,12):
			trench_segments.append([Vector2(x+sin(z*0.09)*5,z),Vector2(x+sin((z+12)*0.09)*5,z+12)])
	# The broad terrain follows Omaha's beach / shingle / bluff / plateau sequence.
	# Detailed fortification placement is authored gameplay, not surveyed geography.
	height_cache_enabled=true
	for i in range(90):
		craters.append({"p":Vector3(rng.randf_range(-330,330),0,rng.randf_range(-167,-16)),"r":rng.randf_range(2.4,5.8),"d":rng.randf_range(0.55,1.0)})
	for i in range(anchors.size()):anchors[i].y=raw_height(anchors[i].x,anchors[i].z)
	snow=ShaderMaterial.new()
	snow.shader=load("res://assets/omaha/coast.gdshader")
	snow.set_shader_parameter("sand_color",load("res://assets/omaha/sand_diff.jpg"))
	snow.set_shader_parameter("sand_normal",load("res://assets/omaha/sand_nor_gl.jpg"))
	snow.set_shader_parameter("stone_color",load("res://assets/omaha/rock_diff.jpg"))
	concrete=textured("concrete",0.33,Color("92998e"))
	masonry=textured("rock",0.24,Color("9c9d8d"))
	for x in range(-int(WIDTH),int(WIDTH),TILE):
		for z in range(-int(DEPTH),144,TILE):ground_chunk(x,z)
	build_coastal_light()
	build_sea()
	build_obstacles()
	build_wire()
	build_seawall()
	for i in range(8):build_bunker(i)
	build_trench_details()
	build_village()
	batch_static_boxes()
	for p in covers:
		var key=Vector2i(floori(p.x/20),floori(p.z/20))
		if not cover_grid.has(key):cover_grid[key]=[]
		cover_grid[key].append(p)
	world_camera=Camera3D.new()
	add_child(world_camera)
	world_camera.position=Vector3(-21,4.0,290)
	world_camera.look_at(Vector3(85,14,-355))
	world_camera.far=2400
	world_camera.fov=74

## Creates a StandardMaterial3D from a tiling texture set in assets/omaha.
## [param kind] texture family ("concrete", "rock"). [param scale_uv] texture repeat scale. [param tint] colour multiplier.
func textured(kind:String,scale_uv:float,tint:Color)->StandardMaterial3D:
	var m=StandardMaterial3D.new()
	m.albedo_color=tint
	m.albedo_texture=load("res://assets/omaha/"+kind+"_diff.jpg")
	m.normal_enabled=true
	m.normal_texture=load("res://assets/omaha/"+kind+"_nor_gl.jpg")
	m.normal_scale=0.65
	m.uv1_triplanar=true
	m.uv1_world_triplanar=true
	m.uv1_scale=Vector3.ONE*scale_uv
	m.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	m.roughness=0.92
	return m

## Terrain height before trenches/craters: below sea level in the water (z > 0), a gentle beach slope capped at 5.45 m, a bluff rising to 42 m between 178 and 313 m inland with three draws (at x = 0 and +-72) forming gentler routes, noise, and a blend to the flat town plateau between 300 and 356 m.
func raw_height(x:float,z:float)->float:
	if z>0:return -0.07*z-0.1
	var beach=minf(-z*0.017,5.45)
	var bluff=smoothstep(178.0,313.0,-z)*42.0
	# Three long draws give infantry a traversable route up the bluffs.
	var draw_distance=minf(absf(x),minf(absf(x-120),absf(x+120)))
	var drawn=lerpf(maxf(0,(-z-174)*0.145),bluff,smoothstep(10,41,draw_distance))
	var h=beach+minf(bluff,drawn)
	h+=noise.get_noise_2d(x,z)*minf(2.1,maxf(0,(-z-5)*0.012))
	return h

## Final terrain height: raw_height, bunker platforms (blend 10 to 21 m), trenches dug up to 1.65 m deep along the trench segments, then another bunker-doorway flattening and shell craters.
## Results are cached once the cache is enabled.
func height_at(x:float,z:float)->float:
	var key=Vector2(x,z)
	if height_cache_enabled and height_cache.has(key):return height_cache[key]
	var h=raw_height(x,z)
	for a in anchors:
		var d=Vector2(x-a.x,z-a.z).length()
		if d<21:h=lerpf(raw_height(a.x,a.z),h,smoothstep(10,21,d))
	if z< -210 and z> -344 and absf(x)<360:
		# Trenches are excavated into the collision surface, not dark painted lines.
		var d=99.0
		for seg in trench_segments:
			if absf(x-seg[0].x)>25 or absf(z-seg[0].y)>25:continue
			var edge=seg[1]-seg[0]
			var t=clampf((Vector2(x,z)-seg[0]).dot(edge)/edge.length_squared(),0,1)
			d=minf(d,Vector2(x,z).distance_to(seg[0]+edge*t))
		h-=1.65*(1.0-smoothstep(1.1,3.2,d))
	# Connecting trenches must not excavate under a bunker doorway and leave an
	# unwalkable concrete sill. Feather a level foundation into the trench bank.
	for a in anchors:
		var distance=Vector2(x-a.x,z-a.z).length()
		if distance<18:h=lerpf(raw_height(a.x,a.z),h,smoothstep(8,18,distance))
	for c in craters:
		var d=Vector2(x-c.p.x,z-c.p.z).length()/c.r
		if d<1.1:h-=c.d*(1.0-smoothstep(0.25,1.0,d))
	if height_cache_enabled:height_cache[key]=h
	return h

## Cell size for a tile at depth z: 2 m between z = -192 and -384 (the fortified belt) and 4 m elsewhere.
func grid_step(z:float)->int:return 2 if z< -192 and z>=-384 else 4

## Builds one terrain tile as a soil Prop with a mesh and a trimesh collider (same idea as the Ardennes chunk).
func ground_chunk(x:float,z:float):
	var body=Prop.new()
	body.material_kind="soil"
	body.battle_world=self
	body.position=Vector3(x,0,z)
	add_child(body)
	var mesh=terrain_mesh(x,z,grid_step(z))
	Art.mesh(body,mesh,Vector3.ZERO,snow)
	var shape=CollisionShape3D.new()
	shape.shape=mesh.create_trimesh_shape()
	body.add_child(shape)
	terrain_chunks.append(body)
	terrain_lookup[Vector2i(int(x),int(z))]=body
	terrain_meshes+=1

## Builds a tile mesh: cells of `step` metres as two triangles, refined to 1 m in cells listed in edited_cells (impact sites).
## [param heights] optional 49 x 49 stored heights of an edited tile; empty means sample height_at.
func terrain_mesh(x:float,z:float,step:int,heights:PackedFloat32Array=PackedFloat32Array())->ArrayMesh:
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for ix in range(0,TILE,step):
		for iz in range(0,TILE,step):
			var a=Vector3(ix,height_at(x+ix,z+iz) if heights.is_empty() else heights[ix*49+iz],iz)
			var b=Vector3(ix+step,height_at(x+ix+step,z+iz) if heights.is_empty() else heights[(ix+step)*49+iz],iz)
			var c=Vector3(ix+step,height_at(x+ix+step,z+iz+step) if heights.is_empty() else heights[(ix+step)*49+iz+step],iz+step)
			var d=Vector3(ix,height_at(x+ix,z+iz+step) if heights.is_empty() else heights[ix*49+iz+step],iz+step)
			tri(st,a,c,b)
			tri(st,a,d,c)
	st.generate_normals()
	st.index()
	return st.commit()

## Terrain height at (x, z) interpolated on the same triangle the mesh uses at this tile's step.
func base_surface_height(x:float,z:float)->float:
	var step=grid_step(floorf(z/TILE)*TILE)
	var gx=floorf(x/step)*step
	var gz=floorf(z/step)*step
	var u=(x-gx)/step
	var v=(z-gz)/step
	var a=height_at(gx,gz)
	var b=height_at(gx+step,gz)
	var c=height_at(gx+step,gz+step)
	var d=height_at(gx,gz+step)
	return a+(b-a)*u+(c-b)*v if u>=v else a+(c-d)*u+(d-a)*v

## Terrain height including shell/shovel edits from soil_edits.
func surface_height(x:float,z:float)->float:
	var key=Vector2i(floori(x/TILE)*TILE,floori(z/TILE)*TILE)
	if not soil_edits.has(key):return base_surface_height(x,z)
	var gx=clampi(floori(x-key.x),0,47)
	var gz=clampi(floori(z-key.y),0,47)
	var u=x-key.x-gx
	var v=z-key.y-gz
	var h:PackedFloat32Array=soil_edits[key]
	var a=h[gx*49+gz]
	var b=h[(gx+1)*49+gz]
	var c=h[(gx+1)*49+gz+1]
	var d=h[gx*49+gz+1]
	return a+(b-a)*u+(c-b)*v if u>=v else a+(c-d)*u+(d-a)*v

## Lowers the terrain inside a sphere by asking each affected tile to carve.
func carve_ground(center:Vector3,radius:float):
	for x in range(floori((center.x-radius)/TILE)*TILE,floori((center.x+radius)/TILE)*TILE+1,TILE):
		for z in range(floori((center.z-radius)/TILE)*TILE,floori((center.z+radius)/TILE)*TILE+1,TILE):
			var body=terrain_lookup.get(Vector2i(x,z))
			if body!=null:body.carve(center,radius)

## Lowers a tile's stored heights to the bottom of a sphere (never more than 2.2 m below the base), marks the touched cells for 1 m refinement, rebuilds the mesh and collider, and calls geometry_updated.
func deform_ground(body,point:Vector3,radius:float):
	var key=Vector2i(roundi(body.position.x),roundi(body.position.z))
	var heights:PackedFloat32Array
	if soil_edits.has(key):heights=soil_edits[key]
	else:
		heights.resize(2401)
		for x in range(49):
			for z in range(49):heights[x*49+z]=base_surface_height(key.x+x,key.y+z)
	for x in range(maxi(0,floori(point.x-radius-key.x)),mini(48,ceili(point.x+radius-key.x))+1):
		for z in range(maxi(0,floori(point.z-radius-key.y)),mini(48,ceili(point.z+radius-key.y))+1):
			var d=Vector2(key.x+x-point.x,key.y+z-point.z).length_squared()
			if d<radius*radius:heights[x*49+z]=minf(heights[x*49+z],maxf(base_surface_height(key.x+x,key.y+z)-2.2,point.y-sqrt(radius*radius-d)))
	soil_edits[key]=heights
	var mesh=terrain_mesh(key.x,key.y,1,heights)
	for child in body.get_children():
		if child is CollisionShape3D:child.shape=mesh.create_trimesh_shape()
	for old in body.owned_meshes():
		old.hide()
		old.queue_free()
	Art.mesh(body,mesh,Vector3.ZERO,snow)
	body.cuts_completed+=1
	body.bounds_valid=false
	geometry_updated(point)

## Bumps the revision, clears the path cache and remembers the change for cover_changed (no grid update; the street grid is rebuilt by build_street_navigation when houses collapse).
func geometry_updated(point:Vector3):
	geometry_revision+=1
	path_cache.clear()
	geometry_changes.append({"revision":geometry_revision,"point":point})
	if geometry_changes.size()>32:geometry_changes.pop_front()

## Route for infantry. In the village (z in front of the town) it joins the
## house interiors' routes (entering by a door, climbing stairs, leaving by the door) with the open street route; nearby teammates (within 6 m on level ground with clear rays) just walk straight; otherwise falls back to the ardennes A* grid.
func path_between(a:Vector3,b:Vector3)->PackedVector3Array:
	return PackedVector3Array([a,b]) # Mission waypoints provide wire / bunker / draw routing.

## Creates a destructible Armor panel with a bevelled box and a collider.
## [param size] metres. [param p] local position. [param mat] material. [param parent] parent node. [param kind] material kind ("masonry", "sandbag", ...). Returns the panel.
func strong(size:Vector3,p:Vector3,mat:Material,parent:Node3D=self,kind:String="masonry"):
	var body=Armor.new()
	body.material_kind=kind
	body.protected_concrete=kind=="masonry"
	body.integrity=40000 if kind=="masonry" else 1800
	body.max_integrity=body.integrity
	body.battle_world=self
	parent.add_child(body)
	body.position=p
	Art.box(body,size,Vector3.ZERO,mat)
	var cs=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=size
	cs.shape=box
	body.add_child(cs)
	return body

## Builds concrete strongpoint `i` with narrow embrasures through thick walls, an open rear doorway, a roof and an MG position, plus a separate sandbag field nest above or below.
func build_bunker(i:int):
	var root=Node3D.new()
	add_child(root)
	root.position=anchors[i]
	strong(Vector3(11,0.4,9),Vector3(0,-0.05,0),concrete,root)
	strong(Vector3(12,1.4,10),Vector3(0,3.0,0),concrete,root)
	# Narrow embrasures are real gaps through thick concrete; rear doorway is open.
	for y in [0.58,2.26]:
		strong(Vector3(10.8,0.85,1.1),Vector3(0,y,4.1),concrete,root)
		for side in [-1,1]:strong(Vector3(1.2,0.85,8.2),Vector3(side*5.0,y,0),concrete,root)
	for x in [-4.2,4.2]:strong(Vector3(2.0,1.5,1.1),Vector3(x,1.4,4.1),concrete,root)
	for side in [-1,1]:
		for z in [-2.8,2.8]:strong(Vector3(1.2,1.5,2.0),Vector3(side*5.0,1.4,z),concrete,root)
		strong(Vector3(3.9,2.6,1.0),Vector3(side*3.25,1.35,-4.1),concrete,root)
		Art.box(root,Vector3(4.0,0.18,9.0),Vector3(side*6,0,0),masonry)
	var stations=[Vector3(0,0.18,2.85),Vector3(-3.6,0.18,0),Vector3(3.6,0.18,0)]
	var bearings=[Vector3(0,0,1),Vector3(-1,0,0.55).normalized(),Vector3(1,0,0.55).normalized()]
	for slot in range(3):
		var p=root.to_global(stations[slot])
		nests.append({"position":p,"kind":"mg42","operator":null,"facing":bearings[slot],"arc":1.05,"bunker":i})
		Art.cylinder(root,0.035,1.02,stations[slot]+Vector3(0,0.50,0),Art.material(Color("353d38")),-1,8)
		Art.box(root,Vector3(0.55,0.24,0.32),stations[slot]+Vector3(0.65,0.15,0.15),Art.material(Color("585b38")))
	bunkers.append({"root":root,"point":anchors[i],"rear":on_ground(anchors[i]+Vector3(0,0,-7)),"secured":false})
	# Each strongpoint also owns a separate lower or upper sandbag MG position.
	var p=on_ground(Vector3(anchors[i].x+26,0,-198 if i%2==0 else -312))
	build_field_nest(p,i)
	for x in [-8.0,8.0]:covers.append(on_ground(anchors[i]+Vector3(x,0,6)))

## Builds a sandbag machine-gun position at `p` (back wall, two side walls, three rows of decorative bags, ammunition box) and registers it with facing +Z and a 1.25 rad arc.
func build_field_nest(p:Vector3,i:int):
	var bag=Art.material(Color("797762"),0,1)
	var root=Node3D.new()
	add_child(root)
	root.position=p
	strong(Vector3(3.5,0.95,0.85),Vector3(0,0.48,1.3),bag,root,"sandbag")
	for side in [-1,1]:strong(Vector3(0.85,1.28,2.5),Vector3(side*1.7,0.64,0.25),bag,root,"sandbag")
	for layer in range(3):
		for x in range(-3,4):Art.beveled_box(root,Vector3(0.48,0.26,0.65),Vector3(x*0.49+(0.12 if layer%2 else 0),0.19+layer*0.27,1.33),bag,0.10)
	Art.box(root,Vector3(0.75,0.45,0.42),Vector3(0.85,0.23,-0.4),Art.material(Color("515639")))
	nests.append({"position":p,"kind":"mg42","operator":null,"facing":Vector3(0,0,1),"arc":1.25,"bunker":i})
	covers.append(p)

## Lays three rows of 8 m wire segments across the beach (spacing from WIRE_EDGE) on the ground, and merges their visuals into batches of 12 per row (hidden individually on a breach).
func build_wire():
	for row in range(3):
		for x in range(-Layout.WIRE_EDGE,Layout.WIRE_EDGE,8):
			var wire=Wire.new()
			wire.game=game
			wire.row=row
			wire.position=on_ground(Vector3(x+4,0,WIRE_ROWS[row]))
			add_child(wire)
			wires.append(wire)
			wires_by_row[row].append(wire)
		# Small batches can be culled independently; a breach hides only its own slot.
		for first in range(0,wires_by_row[row].size(),12):
			var group=wires_by_row[row].slice(first,first+12)
			var poses=[]
			for w in group:poses.append(w.global_transform)
			var key="wire/%d/%d"%[row,first]
			instance_batch(key,Wire.wire_mesh,poses)
			var batch=obstacle_batches[key]
			batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch.visibility_range_end=360
			for i in range(group.size()):
				group[i].bars.hide()
				group[i].visual_batch=batch.multimesh
				group[i].visual_index=i

## Wire segment ahead of a position in a lane, i.e. the first row not yet crossed (null if none or already behind).
## [param p] position. [param lane] lane x.
func blocking_wire(p:Vector3,lane:float):
	for row in range(3):
		if p.z<WIRE_ROWS[row]-2:continue
		var column=clampi(floori((lane+Layout.WIRE_EDGE)/8),0,wires_by_row[row].size()-1)
		return wires_by_row[row][column]
	return null

func nearest_gap(row:int,x:float):
	var chosen=null
	var best=INF
	for wire in gaps_by_row[row]:
		var d=absf(wire.position.x-x)
		if d<best:
			best=d
			chosen=wire
	return chosen

## Builds the sea wall with overlapping breaks that give crawl-height recesses and routes through.
func build_seawall():
	for x in range(-360,360,12):
		# Overlapping breaks provide crawl-height recesses and routes through the wall.
		var p=on_ground(Vector3(x+5,0,Layout.SEAWALL))
		if absf(p.x-Layout.assault_lane(p.x))<12:continue
		strong(Vector3(9.5,1.15,1.5),p+Vector3(0,0.56,0),masonry)
		covers.append(on_ground(p+Vector3(0,0,2.5)))
	for c in craters:covers.append(on_ground(c.p))

## Creates a MultiMeshInstance3D for a mesh and a list of transforms and stores it in obstacle_batches[key].
func instance_batch(key:String,mesh:Mesh,transforms:Array):
	var m=MultiMeshInstance3D.new()
	m.multimesh=MultiMesh.new()
	m.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	m.multimesh.mesh=mesh
	m.multimesh.instance_count=transforms.size()
	for i in range(transforms.size()):m.multimesh.set_instance_transform(i,transforms[i])
	m.visibility_range_end=1300
	add_child(m)
	obstacle_batches[key]=m

## Places Czech hedgehogs (5 rows x 28 columns with random jitter, three crossed beams each, baked to one mesh and instanced) with box colliders and cover points, and 48 mined posts in two rows (instanced; the mine records are kept in `mines`).
func build_obstacles():
	var root=Node3D.new()
	var iron=Art.material(Color("373d36"),0.78,0.72)
	for angle in [Vector3(0,0,PI/4),Vector3(0,0,-PI/4),Vector3(PI/2,0,0)]:
		var beam=Art.box(root,Vector3(0.17,2.45,0.17),Vector3(0,0.78,0),iron)
		beam.rotation=angle
		for side in [-1,1]:
			var flange=Art.box(beam,Vector3(0.24,2.45,0.028),Vector3(0,0,side*0.075),iron)
	var mesh=Kit.bake(root)
	root.free()
	var transforms=[]
	for row in range(5):
		for col in range(46):
			var p=on_ground(Vector3(-338+col*15+rng.randf_range(-2,2),0,-14-row*16+rng.randf_range(-4,4)))
			var xf=Transform3D(Basis(Vector3.UP,rng.randf_range(-PI,PI)),p)
			transforms.append(xf)
			var body=StaticBody3D.new()
			body.collision_layer=1
			body.position=p
			add_child(body)
			var cs=CollisionShape3D.new()
			var box=BoxShape3D.new()
			box.size=Vector3(0.70,1.36,0.70)
			cs.shape=box
			cs.position.y=0.63
			body.add_child(cs)
			covers.append(p+Vector3(0,0,1.3))
	instance_batch("hedgehogs",mesh,transforms)
	root=Node3D.new()
	var wood=Art.material(Color("514b39"))
	var post=Art.cylinder(root,0.15,2.1,Vector3(0,0.75,0),wood,0.11,8)
	post.rotation.x=-0.34
	Art.cylinder(root,0.18,0.11,Vector3(0,1.76,-0.35),iron,-1,12)
	mesh=Kit.bake(root)
	root.free()
	transforms=[]
	for i in range(76):
		var p=on_ground(Vector3(-333+(i%38)*18.0,0,-29-int(i/38)*40))
		transforms.append(Transform3D(Basis.IDENTITY,p))
		mines.append({"point":p,"live":true})
	instance_batch("mined_posts",mesh,transforms)

## Adds a timber duckboard and two upright posts every 12 m along both trench lines (baked into one mesh visible up to 650 m) and a cover point on each.
func build_trench_details():
	var timber=Art.material(Color("534d3d"))
	var root=Node3D.new()
	for x in range(-340,340,12):
		for z in Layout.TRENCHES:
			var p=on_ground(Vector3(x,0,z+sin(x*0.044)*5))
			var board=Art.box(root,Vector3(2.0,0.055,3.6),p+Vector3(0,0.03,0),timber)
			for side in [-1,1]:
				Art.box(root,Vector3(0.12,1.7,0.12),p+Vector3(side*1.7,0.75,0),timber)
			covers.append(p)
	var detail=MeshInstance3D.new()
	detail.mesh=Kit.bake(root)
	detail.visibility_range_end=650
	add_child(detail)
	root.free()

func build_village():
	var roof=Art.material(Color("3b4748"),0.1,0.85)
	var frame=Art.material(Color("444237"))
	var dark=Art.material(Color("131f20"))
	for row in range(3):
		for col in range(24):
			var x=anchors[int(col/3)].x+(col%3-1)*22.0
			# Close house blocks with narrow streets, grouped behind the strongpoints.
			var p=on_ground(Vector3(x,0,Layout.VILLAGE-12-row*24))
			var height=6.0+(col%3)*1.6
			var width=11.0+(col%4)*1.4
			var root=Node3D.new()
			add_child(root)
			root.position=p
			strong(Vector3(width,height,0.6),Vector3(0,height/2,-4.6),masonry,root)
			for side in [-1,1]:strong(Vector3(0.6,height,9.5),Vector3(side*width/2,height/2,0),masonry,root)
			# Front has a physical doorway and firing windows, rather than a solid box.
			for side in [-1,1]:strong(Vector3(width/2-1.1,2.5,0.65),Vector3(side*(width/4+0.55),1.25,4.6),masonry,root)
			strong(Vector3(width,0.75,0.65),Vector3(0,2.88,4.6),masonry,root)
			strong(Vector3(width,maxf(0.4,height-4.5),0.65),Vector3(0,(height+4.5)/2,4.6),masonry,root)
			for xslot in [-width/2,0.0,width/2]:strong(Vector3(0.65,1.5,0.65),Vector3(xslot,3.83,4.6),masonry,root)
			for side in [-1,1]:
				var panel=Art.box(root,Vector3(width+1,0.22,5.7),Vector3(0,height+0.9,side*2.35),roof)
				panel.rotation.x=side*0.36
			Art.box(root,Vector3(0.7,2.3,0.7),Vector3(width*0.23,height+1.4,-1.8),masonry)
			for sx in [-1,1]:
				Art.box(root,Vector3(1.5,1.8,0.12),Vector3(sx*width*0.28,1.3,4.99),frame)
				Art.box(root,Vector3(1.2,1.4,0.12),Vector3(sx*width*0.28,1.4,5.07),dark)
			if town_points.size()<36:town_points.append(p+Vector3(0,0,3.6))
			covers.append(p+Vector3(width/2+1,0,5.7))
	# Ruined road-front cottages sit between the bunkers and below the bluff.
	for a in anchors:
		for offset in [27.0,47.0]:
			var p=on_ground(Vector3(a.x+offset,0,-202))
			strong(Vector3(8,3.8,0.55),p+Vector3(0,1.9,-3.5),masonry)
			for side in [-1,1]:strong(Vector3(0.55,3.8,7),p+Vector3(side*4,1.9,0),masonry)
			for side in [-1,1]:strong(Vector3(2.6,2.4,0.55),p+Vector3(side*2.7,1.2,3.5),masonry)
			var broken_roof=Art.box(self,Vector3(8.5,0.17,4.1),p+Vector3(0,4.3,-1.7),roof)
			broken_roof.rotation.x=-0.42
			covers.append(p+Vector3(0,0,4.3))
	# Church tower makes the inland objective legible from the surf.
	var p=on_ground(Vector3(0,0,Layout.CHURCH))
	strong(Vector3(9,22,9),p+Vector3(0,11,0),masonry)
	Art.cylinder(self,7.1,9,p+Vector3(0,26,0),roof,0,4).rotation.y=PI/4
	for sx in [-1,1]:Art.box(self,Vector3(0.25,4,0.25),p+Vector3(sx*2,32,0),frame)
	Art.box(self,Vector3(5,0.3,0.3),p+Vector3(0,32.8,0),frame)

## Creates the coastal environment (sky, fog, tonemap) and the sun light.
func build_coastal_light():
	ambient=WorldEnvironment.new()
	var env=Environment.new()
	env.background_mode=Environment.BG_SKY
	var sky=Sky.new()
	var material=ProceduralSkyMaterial.new()
	material.sky_top_color=Color("394a55")
	material.sky_horizon_color=Color("929d9e")
	material.ground_bottom_color=Color("414c4a")
	material.ground_horizon_color=Color("929d9e")
	material.sky_curve=0.18
	sky.sky_material=material
	env.sky=sky
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color("b1bfc2")
	env.ambient_light_energy=0.58
	env.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	env.fog_enabled=true
	env.fog_light_color=Color("9daaaa")
	env.fog_density=0.00065
	env.fog_height=1.5
	env.fog_height_density=0.045
	env.fog_sky_affect=0.4
	ambient.environment=env
	add_child(ambient)
	var sun=DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-27,-35,0)
	sun.light_color=Color("dae3df")
	sun.light_energy=1.1
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=95
	add_child(sun)

## Merges every plain box visual (outside nodes flagged skip_static_batch) into MultiMeshes grouped by material and 96 m cell. Groups of fewer than 3 are left alone. Damageable armor panels remember their batch slot and original mesh so they can be unbatched when hit.
func batch_static_boxes():
	# Keep every original collision/damage body. Only their box visuals are instanced.
	# Spatial grouping keeps offscreen village blocks eligible for normal culling.
	var groups={}
	for visual in find_children("*","MeshInstance3D",true,false):
		if not visual.mesh is BoxMesh or not visual.visible:continue
		var mat=visual.material_override
		if mat==null:continue
		var p=visual.global_position
		var key="%s/%d/%d"%[mat.get_instance_id(),floori(p.x/96),floori(p.z/96)]
		if not groups.has(key):groups[key]=[]
		groups[key].append(visual)
	for key in groups:
		var visuals=groups[key]
		if visuals.size()<3:continue
		var mesh=BoxMesh.new()
		mesh.size=Vector3.ONE
		mesh.material=visuals[0].material_override
		var poses=[]
		for visual in visuals:
			poses.append(visual.global_transform*Transform3D(Basis.IDENTITY.scaled(visual.mesh.size),Vector3.ZERO))
		instance_batch("scenery/"+key,mesh,poses)
		var batch=obstacle_batches["scenery/"+key].multimesh
		for i in range(visuals.size()):
			var visual=visuals[i]
			if visual.get_parent() is Armor:
				# Blast distance must retain the original collision-sized bounds
				# after the individual mesh is hidden by its batch.
				visual.get_parent().refresh_bounds()
				visual.get_parent().render_batch=batch
				visual.get_parent().render_index=i
			visual.hide()
		static_batches+=1

## Builds the sea surface.
func build_sea():
	var plane=PlaneMesh.new()
	plane.size=Vector2(7600,3600)
	plane.subdivide_width=32
	plane.subdivide_depth=32
	var mat=ShaderMaterial.new()
	mat.shader=load("res://assets/omaha/sea.gdshader")
	sea=Art.mesh(self,plane,Vector3(0,0,1795),mat)
	sea.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Far coastal silhouette extends the visible shoreline beyond the playable sector.
	for side in [-1,1]:
		var distant=Node3D.new()
		add_child(distant)
		for i in range(18):
			var p=Vector3(side*(620+i*113),8+i*1.2,-302)
			var rock=Art.box(distant,Vector3(120,44,470),p,masonry)
			rock.rotation.z=side*0.017
