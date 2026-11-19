## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/equipment_hitbox.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## A thin hit area attached to a carried item (rifle, mounted gun or sword) so
## that bullets and blows can hit the weapon itself and not only the body.
##
## Role: created by player.gd, enemy.gd and mg_nest.gd for each wielded item; it sits on physics
## layer 16 (the "equipment" layer), which projectile and melee ray tests
## include. Damage is forwarded to the wielder through receive_equipment_damage,
## letting the wielder disarm or flinch when its weapon is shot.
## The area never detects anything itself (mask 0, monitoring off): it is only
## a target.
extends Area3D

## The actor that holds the item; receives damage reports. May be freed, so
## every use goes through is_instance_valid().
var wielder

## Which item this box covers: "rifle", "mounted_gun" or anything else (sword).
## Must be set before the node enters the tree because _ready sizes the shape.
var item: String="rifle"

## Godot lifecycle hook: registers the node in group "equipment_hitbox" and
## builds the box collider sized to the chosen item.
func _ready():
	add_to_group("equipment_hitbox")

	# Layer 16 only; mask 0 and monitoring off because this is a passive target.
	collision_layer=16
	collision_mask=0
	monitoring=false
	var collider=CollisionShape3D.new()
	var shape=BoxShape3D.new()

	# Box dimensions in metres, in the item's local space (-Z is the muzzle
	# direction). The rifle is long and slim; the mounted gun is bulkier;
	# the fallback is an upright blade-like box for the sword.
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

## Turns the hit area on or off by moving it to/from layer 16.
## [param active] true while the item is held out and can be hit; false when
## it is holstered, so shots pass through.
func set_active(active: bool):
	collision_layer=16 if active else 0

## Called by projectile code when this area is struck.
## [param amount] damage points. [param _position] impact point (unused here).
## Forwards to the wielder so one damage model handles body and equipment.
func receive_hit(amount: float, _position: Vector3):
	if is_instance_valid(wielder):wielder.receive_equipment_damage(item,amount)
