# ==============================================================================
# Program: wire.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for wire.gd.
# ==============================================================================
## One 8 m section of barbed-wire entanglement on the Omaha beach.
##
## Wire rows (156 sections in three belts, see layout.gd WIRE_ROWS) block movement. A
## section is opened either by an engineer's Bangalore torpedo (`deploy` then `tick` fuse then
## `breach`) or by repeated hard shovel strokes (`damage_at`). Opening it removes the
## collider, hides the model and records a gap in the world's `gaps_by_row` so AI routing can
## funnel through the breach. The mesh is baked once and shared by all sections.
extends StaticBody3D

# Art helpers.
const Art=preload("res://scripts/art.gd")

# Battle controller (toast, explode, active_charges, world, breach counter).
var game

# Which of the three wire belts (0 = nearest the sea) this section belongs to.
var row:int=0

# True once the section has been opened.
var broken:bool=false

# True while a Bangalore torpedo is placed and burning.
var charge:bool=false

# Seconds left on the fuse.
var fuse:float=0

# Index of the actor who placed the charge (for reporting).
var carrier_index:int=-1

# Node holding the visible wire; hidden when breached.
var bars:Node3D

# Material kind so projectile code treats it as metal.
var material_kind:String="metal"

# Mirrors `broken`, for code that tests `.destroyed` on any destructible.
var destroyed:bool=false

# Section length in metres along x.
var width:float=8.0

# If drawn through a shared MultiMesh, its batch and slot; the slot is zeroed on breach.
var visual_batch:MultiMesh
var visual_index:int=-1

# Shared baked wire mesh, created by the first section.
static var wire_mesh:Mesh

## Build the blocking box collider and the (shared) wire visuals.
func _ready():
	collision_layer=1
	# Layer 1 is the world; mask 0 because wire only receives hits.
	collision_mask=0
	var shape=CollisionShape3D.new()
	var box=BoxShape3D.new()
	# Collider 8 m wide, 1.25 m tall and 1.45 m deep, matching the coil footprint.
	box.size=Vector3(width,1.25,1.45)
	shape.shape=box
	shape.position.y=0.65
	add_child(shape)
	bars=Node3D.new()
	add_child(bars)
	# Build the visual wire mesh once for all sections.
	if wire_mesh==null:
		var root=Node3D.new()
		var iron=Art.material(Color("414a44"),0.70,0.8)
		# Three slanted posts (one at x = -4, 0 and 4) holding the wires.
		for x in [-4.0,0.0,4.0]:
			strand(root,Vector3(x,0,-0.55),Vector3(x,1.35,0.4),0.025,iron)
		# Three horizontal wires along the section at heights 0.28, 0.67 and 1.03 m.
		for line in [0.28,0.67,1.03]:
			strand(root,Vector3(-4,line,0),Vector3(4,line,0),0.012,iron)
		# A coiled spiral (concertina) of 48 short wire segments over the 8 m length, six per metre, radius about 0.55 m; every third segment gets a barb.
		for i in range(48):
			var a=i*TAU/6
			var b=(i+1)*TAU/6
			strand(root,Vector3(-4+i/6.0,0.65+sin(a)*0.54,cos(a)*0.58),Vector3(-4+(i+1)/6.0,0.65+sin(b)*0.54,cos(b)*0.58),0.014,iron)
			if i%3==0:strand(root,Vector3(-4+i/6.0-0.07,0.56+sin(a)*0.54,cos(a)*0.58),Vector3(-4+i/6.0+0.07,0.74+sin(a)*0.54,cos(a)*0.58),0.012,iron)
		# Bake all segments into one mesh so a section costs one draw call.
		wire_mesh=preload("res://scripts/ardennes/weapons.gd").bake(root)
		root.free()
	var mesh=MeshInstance3D.new()
	mesh.mesh=wire_mesh
	# No shadows and a 380 m visibility range keep 156 sections cheap.
	mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visibility_range_end=380
	bars.add_child(mesh)

## Add a thin 4-sided wire segment (no end caps) between two points.
func strand(parent:Node3D,a:Vector3,b:Vector3,radius:float,mat:Material):
	var mesh=Art.segment(parent,a,b,radius,mat)
	mesh.mesh.radial_segments=4
	mesh.mesh.rings=1
	mesh.mesh.cap_top=false
	mesh.mesh.cap_bottom=false

## Place a Bangalore torpedo on this section.
## @param actor The engineer; needs `bangalores`, `index`, `alive` and a position within 4.2 m.
## @return true if the charge was placed (consumes one torpedo); false if not possible.
func deploy(actor)->bool:
	if broken or charge or not actor.alive or actor.bangalores<=0:return false
	if actor.position.distance_to(position)>4.2:return false
	actor.bangalores-=1
	charge=true
	# Fixed 2 s fuse gives the engineer time to move away and the player a warning.
	fuse=2.0
	game.active_charges.append(self)
	carrier_index=actor.index
	# Visual: a 5 m pipe lying along the wire.
	var tube=Art.cylinder(self,0.045,5.0,Vector3(0,0.10,0),Art.material(Color("746c40")),-1,10)
	tube.rotation.x=PI/2
	game.toast("BANGALORE SET • CLEAR THE WIRE",3)
	return true

## Advance the fuse; breach and explode at zero.
## @param delta Seconds.
func tick(delta:float):
	if not charge or broken:return
	fuse-=delta
	if fuse<=0:
		breach()
		# The blast (6 m radius, 140 damage) also hurts soldiers close to the wire.
		game.explode(position+Vector3(0,0.2,0),6.0,140,null,"bangalore")

## Open the section permanently.
func breach():
	if broken:return
	broken=true
	destroyed=true
	collision_layer=0
	# Hide the bars and remove collision; batched sections are hidden by a zero-scale transform.
	bars.hide()
	if visual_batch!=null:visual_batch.set_instance_transform(visual_index,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),position))
	# Register in the row's gap list and let AI navigation know the geometry changed.
	game.world.gaps_by_row[row].append(self)
	game.world.geometry_updated(position)
	game.breaches+=1
	game.toast("WIRE BREACHED • A LOCAL GAP IS OPEN",4)

## Take damage; only strong non-explosive hits (shovel-like, 90 or more) count, 16 of them open the section.
## @return Always true: the wire absorbs the hit.
func damage_at(amount:float,_point:Vector3,_radius:float=0.2,explosive:bool=false)->bool:
	# Rifle bullets and fragmentation do not conveniently erase entire wire rows.
	# A player can finish an isolated segment with repeated close shovel strokes.
	# Rifle bullets and fragmentation do not conveniently erase entire wire rows.
	# A player can finish an isolated segment with repeated close shovel strokes.
	if not explosive and amount>=90:
		set_meta("cuts",int(get_meta("cuts",0))+1)
		if int(get_meta("cuts",0))>=16:breach()
	return true
