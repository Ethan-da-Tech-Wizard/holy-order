extends Node3D
# Three occupied levels share static geometry. Only damaged panels are rebuilt.
const Art=preload("res://scripts/art.gd")
const Kit=preload("res://scripts/ardennes/weapons.gd")
var world
var index:int=0
var panels:Array=[]
var supports:Array=[]
var stations:Array=[]
var collapsed:bool=false
var decorative:Node3D
var rubble:Array=[]
var facade:Material
var timber:Material
var roof_material:Material

func _ready():
	facade=world.town_materials[index%world.town_materials.size()]
	timber=world.town_timber
	roof_material=world.town_roofs[index%2]
	decorative=Node3D.new()
	add_child(decorative)
	# Continuous side walls, opening onto two streets through front/back doors.
	for side in [-1,1]:
		panel(Vector3(0.6,9.6,26),Vector3(side*11,4.8,0),facade,2400)
		for z in [-12.7,0.0,12.7]:
			var pier=panel(Vector3(0.85,3.2,1.1),Vector3(side*10.65,1.6,z),facade,1100)
			supports.append(pier)
	for side in [-1,1]:
		var z=side*12.7
		for floor_id in range(3):
			var y=floor_id*3.2
			# The ground-floor middle opening is a genuine walk-through doorway.
			for x in [-6.2,6.2]:panel(Vector3(9.6,0.85,0.6),Vector3(x,y+0.425,z),facade)
			if floor_id>0:panel(Vector3(2.8,0.85,0.6),Vector3(0,y+0.425,z),facade)
			panel(Vector3(22,0.85,0.6),Vector3(0,y+2.775,z),facade)
			var spans=[Vector2(-11,-6.75),Vector2(-4.85,-1.4),Vector2(1.4,4.85),Vector2(6.75,11)] if floor_id==0 else [Vector2(-11,-6.75),Vector2(-4.85,4.85),Vector2(6.75,11)]
			for span in spans:
				var x=(span.x+span.y)*0.5
				var pier=panel(Vector3(span.y-span.x,1.5,0.6),Vector3(x,y+1.6,z),facade,900)
				if floor_id==0 and absf(x)<6:supports.append(pier)
			# Window reveals and shutters stay clear of the firing apertures.
			for x in [-5.8,5.8]:
				panel(Vector3(2.25,0.10,0.85),Vector3(x,y+0.89,z),timber,160)
				for edge in [-1,1]:
					Art.box(decorative,Vector3(0.52,1.48,0.12),Vector3(x+edge*1.18,y+1.62,z+side*0.38),world.town_shutters[index%3])
	# Floor plates leave a real stairwell; wide landings at both ends.
	for floor_id in [1,2]:
		var y=floor_id*3.2
		panel(Vector3(18,0.24,25.5),Vector3(-1.9,y-0.12,0),timber,1600)
		for z in [-8.9,8.9]:panel(Vector3(3.6,0.24,7.5),Vector3(8.8,y-0.12,z),timber,650)
		var stair=panel(Vector3(2.8,0.20,10.5),Vector3(8.55,y-1.65,0),timber,800)
		stair.rotation.x=atan2(3.2,10.0)
		# A smooth collision ramp under shallow visual stair treads avoids foot snagging.
		for step in range(16):
			var sy=(floor_id-1)*3.2+step*0.2
			Art.box(decorative,Vector3(2.8,0.10,0.625),Vector3(8.55,sy+0.02,4.68-step*0.625),timber)
		Art.segment(decorative,Vector3(6.98,y-2.3,4.8),Vector3(6.98,y+0.8,-4.8),0.04,timber)
	# Slate/terracotta, gutters, chimney and exposed timbers give each block a roofline.
	for side in [-1,1]:
		var roof=panel(Vector3(23.5,0.25,13.7),Vector3(0,10.6,side*6.6),roof_material,1250)
		roof.rotation.x=side*0.16
		Art.box(decorative,Vector3(23.5,0.15,0.15),Vector3(0,9.48,side*13.3),world.town_metal)
	panel(Vector3(1.15,2.1,1.15),Vector3(-7,11.2,-4.6),facade,850)
	for x in [-8,0,8]:Art.box(decorative,Vector3(0.18,0.24,25.5),Vector3(x,6.16,0),timber)
	# Broken plaster patches, masonry footing and lintels use the same masonry palette.
	for i in range(5):
		Art.box(decorative,Vector3(1.4+(i%2),0.22,0.015),Vector3(-9+i*4.4,0.25+(i%3)*0.22,13.015),world.town_brick)
	var sign=Label3D.new()
	decorative.add_child(sign)
	sign.text=["RUE DE L'ÉGLISE","RUE DU PORT","RUE DES ÉCOLES"][index/8]
	sign.font_size=32
	sign.pixel_size=0.010
	sign.position=Vector3(-8.5,2.65,13.03)
	sign.modulate=Color("c7d5d8")
	sign.outline_modulate=Color("24404c")
	sign.no_depth_test=false
	for entry in [
		[Vector3(-5.8,3.22,11.45),"mg42",Vector3.BACK],
		[Vector3(5.8,3.22,11.45),"g43",Vector3.BACK],
		[Vector3(-5.8,6.42,-11.45),"mg42" if index%2==0 else "kar98",Vector3.FORWARD],
		[Vector3(5.8,0.03,11.45),"mp40" if index%3==0 else "kar98",Vector3.BACK]]:
		stations.append({"point":position+entry[0],"kind":entry[1],"facing":entry[2],"indoor":true})
		if entry[1]=="mg42":
			var s=entry[0]
			Art.cylinder(decorative,0.035,1.1,s+Vector3(0,0.54,0),world.town_metal,-1,8)
			panel(Vector3(1.8,0.7,0.55),s+Vector3(0,0.32,entry[2].z*0.75),world.town_bags,650,"sandbag")
	# Bake unbreakable fittings once per house; they disappear with its shell.
	var mesh=MeshInstance3D.new()
	mesh.mesh=Kit.bake(decorative)
	for child in decorative.get_children():
		if child is MeshInstance3D:child.queue_free()
	decorative.add_child(mesh)
	decorative.set_meta("skip_static_batch",true)

func panel(size:Vector3,p:Vector3,mat:Material,hp:float=950,kind:String="masonry"):
	if mat==timber and kind=="masonry":kind="wood"
	var body=world.strong(size,p,mat,self,kind)
	body.protected_concrete=false
	body.integrity=hp
	body.max_integrity=hp
	body.structure=self
	panels.append(body)
	return body

func contains(p:Vector3,padding:float=0.0)->bool:
	var local=p-position
	return absf(local.x)<11+padding and absf(local.z)<13+padding

func floor_at(p:Vector3)->int:
	return clampi(roundi((p.y-position.y)/3.2),0,2)

func route_inside(start:Vector3,goal:Vector3)->PackedVector3Array:
	var path=PackedVector3Array()
	var floor_id=floor_at(start) if contains(start) else 0
	if not contains(start):
		var side=1 if start.z>position.z else -1
		path.append(position+Vector3(0,0.04,side*15.0))
		path.append(position+Vector3(0,0.04,side*10.0))
	var final_floor=floor_at(goal) if contains(goal) else 0
	while floor_id<final_floor:
		path.append(position+Vector3(5.1,floor_id*3.2+0.03,6.2))
		path.append(position+Vector3(8.55,floor_id*3.2+0.03,5.5))
		path.append(position+Vector3(8.55,(floor_id+1)*3.2+0.03,-5.5))
		path.append(position+Vector3(5.1,(floor_id+1)*3.2+0.03,-6.2))
		floor_id+=1
	while floor_id>final_floor:
		path.append(position+Vector3(5.1,floor_id*3.2+0.03,-6.2))
		path.append(position+Vector3(8.55,floor_id*3.2+0.03,-5.5))
		path.append(position+Vector3(8.55,(floor_id-1)*3.2+0.03,5.5))
		path.append(position+Vector3(5.1,(floor_id-1)*3.2+0.03,6.2))
		floor_id-=1
	if not contains(goal):path.append(position+Vector3(0,0.04,15 if goal.z>position.z else -15))
	path.append(goal)
	return path

func check_supports():
	if collapsed or supports.is_empty():return
	var capacity=0.0
	var footprint=PackedVector2Array()
	for support in supports:
		if support.destroyed:continue
		var fraction=clampf(support.integrity/support.max_integrity,0,1)
		capacity+=fraction
		if fraction>0.2:footprint.append(Vector2(support.position.x,support.position.z))
	# Load must remain both substantial and distributed around the centre of mass.
	var stable=capacity>=supports.size()*0.34 and footprint.size()>=3
	if stable:stable=Geometry2D.is_point_in_polygon(Vector2.ZERO,Geometry2D.convex_hull(footprint))
	if not stable:collapse()

func collapse():
	if collapsed:return
	collapsed=true
	for panel_body in panels:
		panel_body.structure=null
		panel_body.demolish()
	decorative.hide()
	# Kill occupants of the falling shell, including soldiers on upper floors.
	for actor in world.game.actors+[world.game.player]:
		if world.game.actor_alive(actor) and contains(actor.position) and actor.position.y>position.y-0.5 and actor.position.y<position.y+11.5:
			world.game.hurt_actor(actor,10000,position,"collapse")
	for tank in world.game.tanks:
		if tank.alive and contains(tank.position):tank.hull_damage(250,position)
	for i in range(8):
		var p=Vector3(-8+(i%4)*5.3,0.35+(i%3)*0.13,-7+int(i/4)*14)
		var chunk=world.strong(Vector3(4.4,0.7+(i%3)*0.26,4.0),p,facade,self,"masonry")
		chunk.protected_concrete=false
		chunk.integrity=500
		chunk.max_integrity=500
		rubble.append(chunk)
		world.street_obstacles.append({"body":chunk,"rect":Rect2(Vector2(position.x+p.x-2.8,position.z+p.z-2.6),Vector2(5.6,5.2))})
	world.geometry_updated(position)
	world.build_street_navigation()
	if world.game.player.position.distance_to(position)<200:world.game.sounds.at("explosion",position,-9,0.65)
