# ==============================================================================
# Program: dropped_weapon.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for dropped_weapon.gd.
# ==============================================================================
## A weapon lying on the ground that the player can swap for.
##
## Spawned when a soldier dies or a gun is dropped. `kind` selects the model in
## weapons.gd; `rounds` is the ammo left in it and `condition` its health. The
## player's use action calls `take(player)`, which exchanges weapons via the game script.
extends StaticBody3D
const Kit=preload("res://scripts/ardennes/weapons.gd")

# Game controller; provides swap_weapon() and (optionally) batch_remains().
var game

# Weapon key understood by weapons.gd (e.g. "bar").
var kind:String="bar"
var rounds:int=0

# Condition 0-100; shooting a dropped weapon damages it.
var condition:float=100
var picked_up:bool=false

# Fixed-gun pickup: cannot be taken and stays upright.
var mounted:bool=false
var model:Node3D

## Build the model and a pickup collider.
func _ready():
	add_to_group("dropped_weapons")
	collision_layer=32
	# Layer 32 = interactive pickups; the player's use ray looks for it.
	collision_mask=0
	model=Kit.weapon(self,kind)
	# Lay the weapon on its side unless it is a mounted gun.
	model.rotation.z=0 if mounted else PI/2
	var cs=CollisionShape3D.new()
	var box=BoxShape3D.new()
	# Box roughly the size of a rifle (1.2 m long) so it is easy to aim at.
	box.size=Vector3(0.22,0.12,1.2)
	cs.shape=box
	cs.position.z=-0.22
	add_child(cs)

## Damage the weapon when shot (it is not destroyed, just ruined).
func receive_hit(amount:float,_point:Vector3):
	condition=maxf(0,condition-amount)
	if condition==0:model.rotation.x=0.08

## Swap this weapon with the player's current one.
## @return true if taken, false if already taken or mounted.
func take(player):
	if picked_up or mounted:return false
	# Game script handles inventory and drops the old weapon.
	game.swap_weapon(self)
	picked_up=true
	collision_layer=0
	queue_free()
	return true
