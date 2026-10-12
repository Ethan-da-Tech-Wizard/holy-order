extends "res://scripts/breakable.gd"

var battle_world
var tree_health: float = 0
var is_tree: bool = false
var wear:float=0
var truck_owner

func damage_at(amount: float, point: Vector3, radius: float=0.24, explosive: bool=false) -> bool:
	if destroyed:return false
	if material_kind=="soil" and not explosive and radius<0.3:return false
	wear+=amount
	# Bound the complexity of repeatedly chipped cover. Worn-out pieces collapse
	# completely; they never become invulnerable because the cut budget was reached.
	if not is_tree and material_kind!="soil":
		var failure={"wood":240.0,"cloth":40.0,"sandbag":640.0,"rock":1700.0,"metal":1100.0}.get(material_kind,900.0)
		if wear>=failure:
			if truck_owner!=null:truck_owner.receive_part_damage(amount,point,explosive)
			demolish()
			return true
		if cuts_completed>=12 and not explosive:return false
	if truck_owner != null:
		truck_owner.receive_part_damage(amount,point,explosive)
	if is_tree:
		tree_health -= amount
		if tree_health <= 0:
			# A severed trunk topples as a whole, then becomes low deadwood cover.
			battle_world.fell_tree(self)
			return true
	return super.damage_at(amount,point,radius,explosive)

func carve(point: Vector3, radius: float):
	if destroyed:return
	if battle_world != null:
		battle_world.queue_cut(self,point,radius)
	else:
		super.carve(point,radius)

func commit_cut(point: Vector3, radius: float):
	if material_kind=="soil" and battle_world!=null:
		battle_world.deform_ground(self,point,radius)
	else:super.carve(point,radius)
