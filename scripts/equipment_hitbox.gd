extends Area3D

var wielder
var item: String="rifle"

func _ready():
	add_to_group("equipment_hitbox")
	collision_layer=16
	collision_mask=0
	monitoring=false
	var collider=CollisionShape3D.new()
	var shape=BoxShape3D.new()
	if item=="rifle":
		shape.size=Vector3(0.075,0.12,1.27)
		collider.position=Vector3(0,-0.015,-0.235)
	elif item=="mounted_gun":
		shape.size=Vector3(0.22,0.24,1.45)
		collider.position=Vector3(0,0,-0.34)
	else:
		shape.size=Vector3(0.12,1.0,0.05)
		collider.position=Vector3(0,0.58,0)
	collider.shape=shape
	add_child(collider)

func set_active(active: bool):
	collision_layer=16 if active else 0

func receive_hit(amount: float, _position: Vector3):
	if is_instance_valid(wielder):wielder.receive_equipment_damage(item,amount)
