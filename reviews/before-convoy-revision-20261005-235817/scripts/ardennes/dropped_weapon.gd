extends StaticBody3D
const Kit=preload("res://scripts/ardennes/weapons.gd")
var game
var kind:String="bar"
var rounds:int=0
var condition:float=100
var picked_up:bool=false
var mounted:bool=false
var model:Node3D

func _ready():
	add_to_group("dropped_weapons")
	collision_layer=32
	collision_mask=0
	model=Kit.weapon(self,kind)
	model.rotation.z=0 if mounted else PI/2
	var cs=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=Vector3(0.22,0.12,1.2)
	cs.shape=box
	cs.position.z=-0.22
	add_child(cs)

func receive_hit(amount:float,_point:Vector3):
	condition=maxf(0,condition-amount)
	if condition==0:model.rotation.x=0.08

func take(player):
	if picked_up or mounted:return false
	game.swap_weapon(self)
	picked_up=true
	collision_layer=0
	queue_free()
	return true
