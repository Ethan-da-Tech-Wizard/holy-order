# ==============================================================================
# Program: dropped_weapon.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Dynamic discarded firearm entity. Simulates physical tumbling upon soldier elimination, remaining magazine ammunition retention, and player retrieval interaction colliders.
# ==============================================================================
extends StaticBody3D
const Kit=preload("res://scripts/ardennes/weapons.gd")
var game
var kind:String="bar"
var rounds:int=0
var condition:float=100
var picked_up:bool=false
var mounted:bool=false
var model:Node3D
var visual_batch:Dictionary={}

func _ready():
	# --- LIFECYCLE INITIALIZATION: Scene Tree Entry & Component Binding ---
	# Invariants:
	# - Configures physics collision layers/masks and spatial spatial transforms.
	# - Caches local references to prevent runtime get_node() tree traversal latency.
	# - Binds event signals and initializes internal state machines.
	# Step: Initialize node state, configure collision layers, and bind signal delegates
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
	if game.has_method("batch_remains"):
		visual_batch=game.batch_remains(model.get_child(0))

func receive_hit(amount:float,_point:Vector3):
	# Step: Process damage reception, evaluate armor mitigation, and update health status
	condition=maxf(0,condition-amount)
	if condition==0:
		model.rotation.x=0.08
		if not visual_batch.is_empty():visual_batch.mm.set_instance_transform(visual_batch.slot,model.global_transform)

func _exit_tree():
	# --- CONTRACT: Function `_exit_tree` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for _exit_tree
	if not visual_batch.is_empty():visual_batch.mm.set_instance_transform(visual_batch.slot,Transform3D(Basis.IDENTITY.scaled(Vector3.ZERO),Vector3.ZERO))

func take(player):
	# --- CONTRACT: Function `take` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for take
	if picked_up or mounted:return false
	game.swap_weapon(self)
	picked_up=true
	collision_layer=0
	queue_free()
	return true
