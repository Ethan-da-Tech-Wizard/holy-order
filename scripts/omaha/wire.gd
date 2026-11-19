## One 8 m segment of barbed wire on the Omaha beach.
##
## Role: placed by the Omaha world in rows (Layout.WIRE_ROWS). It blocks movement
## (collision layers 1 and 128, the latter used by AI to recognise wire) until
## it is breached: by an engineer's bangalore torpedo (deploy(), a 2 s fuse then
## an explosion), by 16 close shovel strikes, or by blasts. A breach opens a
## local gap that the AI paths through (world.gaps_by_row).
## The model is a shared baked mesh (static `wire_mesh`) of posts, rails and a
## helical coil, so the beach can hold many segments cheaply.
extends StaticBody3D
const Art=preload("res://scripts/art.gd")

## The Omaha battle controller.
var game

## Index of the wire row (0 at the sea side).
var row:int=0

## True once a gap has been opened.
var broken:bool=false

## True while a bangalore is set and burning.
var charge:bool=false

## Seconds until the charge explodes (2 s).
var fuse:float=0

## Index of the engineer who set the charge.
var carrier_index:int=-1

## Visual node holding the wire mesh.
var bars:Node3D

## Always "metal"; allows shared damage code to treat wire like a prop.
var material_kind:String="metal"

## Mirrors `broken` for code that checks destroyed bodies.
var destroyed:bool=false

## Segment length along x in metres (8).
var width:float=8.0

## MultiMesh slot if the visual was batched by the world, else null.
var visual_batch:MultiMesh

## Slot index in visual_batch.
var visual_index:int=-1

## The single shared baked wire mesh.
static var wire_mesh:Mesh

## Godot lifecycle hook: sets collision (box 8 x 1.25 x 1.45 m) and builds the shared mesh on first use (3 posts, 3 horizontal strands, and a 48-step helical coil with barbs), visible up to 380 m.
func _ready():
	collision_layer=1|128
	collision_mask=0
	var shape=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=Vector3(width,1.25,1.45)
	shape.shape=box
	shape.position.y=0.65
	add_child(shape)
	bars=Node3D.new()
	add_child(bars)
	if wire_mesh==null:
		var root=Node3D.new()
		var iron=Art.material(Color("414a44"),0.70,0.8)
		for x in [-4.0,0.0,4.0]:
			strand(root,Vector3(x,0,-0.55),Vector3(x,1.35,0.4),0.025,iron)
		for line in [0.28,0.67,1.03]:
			strand(root,Vector3(-4,line,0),Vector3(4,line,0),0.012,iron)
		for i in range(48):
			var a=i*TAU/6
			var b=(i+1)*TAU/6
			strand(root,Vector3(-4+i/6.0,0.65+sin(a)*0.54,cos(a)*0.58),Vector3(-4+(i+1)/6.0,0.65+sin(b)*0.54,cos(b)*0.58),0.014,iron)
			if i%3==0:strand(root,Vector3(-4+i/6.0-0.07,0.56+sin(a)*0.54,cos(a)*0.58),Vector3(-4+i/6.0+0.07,0.74+sin(a)*0.54,cos(a)*0.58),0.012,iron)
		wire_mesh=preload("res://scripts/ardennes/weapons.gd").bake(root)
		root.free()
	var mesh=MeshInstance3D.new()
	mesh.mesh=wire_mesh
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visibility_range_end=380
	bars.add_child(mesh)

## Adds one thin low-poly rod between two points (4 sides, open ended) to build the wire model.
func strand(parent:Node3D,a:Vector3,b:Vector3,radius:float,mat:Material):
	var mesh=Art.segment(parent,a,b,radius,mat)
	mesh.mesh.radial_segments=4
	mesh.mesh.rings=1
	mesh.mesh.cap_top=false
	mesh.mesh.cap_bottom=false

## Sets a bangalore torpedo on this segment. Fails if broken, already charged, the engineer is dead, has none left, or is more than 4.2 m away.
## [param actor] the engineer. Returns true if the charge was set.
func deploy(actor)->bool:
	if broken or charge or not actor.alive or actor.bangalores<=0:return false
	if actor.position.distance_to(position)>4.2:return false
	actor.bangalores-=1
	charge=true
	fuse=2.0
	game.active_charges.append(self)
	carrier_index=actor.index
	var tube=Art.cylinder(self,0.045,5.0,Vector3(0,0.10,0),Art.material(Color("746c40")),-1,10)
	tube.rotation.x=PI/2
	game.toast("BANGALORE SET • CLEAR THE WIRE",3)
	return true

## Counts down the fuse each physics step (called by the battle controller) and explodes: breaches the wire and detonates 6 m / 140 damage at the segment.
## [param delta] seconds.
func tick(delta:float):
	if not charge or broken:return
	fuse-=delta
	if fuse<=0:
		breach()
		game.explode(position+Vector3(0,0.2,0),6.0,140,null,"bangalore")

## Opens the gap: removes collision and the visual, registers the gap with the world for pathing, counts the breach and shows a toast.
func breach():
	if broken:return
	broken=true
	destroyed=true
	collision_layer=0
	bars.hide()
	if visual_batch!=null:visual_batch.set_instance_transform(visual_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),position))
	game.world.gaps_by_row[row].append(self)
	game.world.geometry_updated(position)
	game.breaches+=1
	game.toast("WIRE BREACHED • A LOCAL GAP IS OPEN",4)

## Wire resists ordinary weapons: only hits of 90 damage or more (shovel strikes) count as cuts; 16 cuts breach. Always returns true.
## [param amount] damage points. [param explosive] true for blasts (ignored here).
func damage_at(amount:float,_point:Vector3,_radius:float=0.2,explosive:bool=false)->bool:
	# Rifle bullets and fragmentation do not conveniently erase entire wire rows.
	# A player can finish an isolated segment with repeated close shovel strokes.
	if not explosive and amount>=90:
		set_meta("cuts",int(get_meta("cuts",0))+1)
		if int(get_meta("cuts",0))>=16:breach()
	return true
