extends Node3D

const Art=preload("res://scripts/art.gd")
var leaf
var opened: bool=false
var moving: bool=false
var base_angle: float=0
var width: float=1.72

func _ready():
	add_to_group("field_door")
	base_angle=rotation.y
	leaf=Art.solid(self,Vector3(width,2.18,0.10),Vector3(width/2,1.09,0),Art.material(Color("514937")),0,"wood")
	for y in [0.45,1.55]:
		Art.box(leaf,Vector3(width-0.05,0.10,0.035),Vector3(0,y-1.09,-0.065),Art.material(Color("3c3e36"),0.5))
	Art.sphere(leaf,0.035,Vector3(width/2-0.15,0.02,-0.087),Art.material(Color("6e6650"),0.7))
	leaf.geometry_changed.connect(func():
		if leaf.destroyed: moving=false
	)

func available() -> bool:
	return is_instance_valid(leaf) and not leaf.destroyed

func use():
	if moving or not available():return
	opened=not opened
	moving=true
	var tween=create_tween()
	tween.tween_property(self,"rotation:y",base_angle+(-1.63 if opened else 0.0),0.42).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		moving=false
		var worlds=get_tree().get_nodes_in_group("battle_world")
		if not worlds.is_empty():worlds[0].geometry_updated(global_position)
	)

func interaction_position() -> Vector3:
	return to_global(Vector3(width/2,1.0,0))
