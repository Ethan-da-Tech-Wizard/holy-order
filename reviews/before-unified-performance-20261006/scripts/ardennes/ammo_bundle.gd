extends StaticBody3D
const Art=preload("res://scripts/art.gd")
var game
var contents:Array=[]
func _ready():
	add_to_group("ammo_bundles")
	collision_layer=32
	collision_mask=0
	Art.beveled_box(self,Vector3(0.40,0.25,0.32),Vector3.ZERO,Art.material(Color("786a4a")),0.04)
	var cs=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=Vector3(0.40,0.25,0.32)
	cs.shape=box
	add_child(cs)
func take(player):
	var total=0
	for item in contents.duplicate():
		var n=player.ammo_pack.add_rounds(item.kind,item.rounds)
		item.rounds-=n
		total+=n
		if item.rounds==0:contents.erase(item)
	if contents.is_empty():queue_free()
	game.toast("Recovered %d rounds. Pack %.1f / 24 space."%[total,player.ammo_pack.space_used()],3)
func receive_hit(_amount:float,_point:Vector3):pass
