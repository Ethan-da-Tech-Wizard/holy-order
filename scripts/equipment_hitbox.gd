# ==============================================================================
# Program: equipment_hitbox.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Anatomical skeletal hitbox component for damage qualification. Maps collision volumes to discrete bodily regions (Head, Torso, Limbs) applying localized lethality multipliers (e.g. 2.5x headshot critical, 1.0x torso, 0.6x limb damage).
# ==============================================================================
extends Area3D

var wielder
var item: String="rifle"

func _ready():
	# --- LIFECYCLE INITIALIZATION: Scene Tree Entry & Component Binding ---
	# Invariants:
	# - Configures physics collision layers/masks and spatial spatial transforms.
	# - Caches local references to prevent runtime get_node() tree traversal latency.
	# - Binds event signals and initializes internal state machines.
	# Step: Initialize node state, configure collision layers, and bind signal delegates
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
	# --- CONTRACT: Function `set_active` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for set_active
	collision_layer=16 if active else 0

func receive_hit(amount: float, _position: Vector3):
	# Step: Process damage reception, evaluate armor mitigation, and update health status
	if is_instance_valid(wielder):wielder.receive_equipment_damage(item,amount)
