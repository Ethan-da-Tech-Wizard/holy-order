# ==============================================================================
# Program: equipment_hitbox.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for equipment_hitbox.gd.
# ==============================================================================
## Hitbox for a held item (rifle, mounted gun or other) so shots can hit gear.
##
## Lives on physics layer 16 so bullets can strike a soldier's weapon separately
## from his body; the damage is forwarded to the wielder through
## `receive_equipment_damage`. `wielder` and `item` must be set by the spawner
## before the node enters the tree because the shape is built in _ready.
extends Area3D

# The character holding the item; forwarded damage target. May be freed while the box lives.
var wielder

# Item kind selecting the box shape: "rifle", "mounted_gun", anything else is treated as a long-handled tool.
var item: String="rifle"

func _ready():
	# Joined to a group so shot logic and debugging can find all equipment hitboxes at once.
	add_to_group("equipment_hitbox")
	# Layer 16 holds equipment; mask 0 because the box only receives hits and never detects anything.
	collision_layer=16
	collision_mask=0
	# monitoring is off for performance: an Area3D used purely as a hit target needs no overlap events.
	monitoring=false
	var collider=CollisionShape3D.new()
	var shape=BoxShape3D.new()
	# Dimensions (metres) approximate each item: a thin 1.27 m rifle, a bulkier 1.45 m gun, else a tall narrow stick.
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

## Enable or disable the hitbox (e.g. when the item is holstered).
## @param active true to put the box back on layer 16, false to remove it from all layers.
func set_active(active: bool):
	collision_layer=16 if active else 0

## Forward a bullet hit to the wielder as equipment damage.
## @param amount Damage points.
## @param _position World impact point (unused; part of the common receive_hit interface).
func receive_hit(amount: float, _position: Vector3):
	# Guard against the wielder dying and being freed before the bullet resolves.
	if is_instance_valid(wielder):wielder.receive_equipment_damage(item,amount)
