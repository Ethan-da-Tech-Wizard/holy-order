## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/ardennes/dropped_weapon.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## A weapon lying on the ground (dropped by a dead soldier or sitting on a
## mounted emplacement) that the player can pick up to swap weapons.
##
## Role: spawned by the battle script; `game` handles the actual swap
## (swap_weapon). The model comes from weapons.gd (`Kit`). Collision layer 32
## (pickups). Shots can damage it: at 0 condition the weapon is considered
## ruined and visually tilts.
extends StaticBody3D
const Kit=preload("res://scripts/ardennes/weapons.gd")

## The battle controller (swap_weapon, batch_remains).
var game

## Weapon type key understood by weapons.gd (default "bar", the M1918A2 BAR).
var kind:String="bar"

## Rounds still in the weapon.
var rounds:int=0

## Durability 0..100; hits reduce it and at 0 the weapon is ruined.
var condition:float=100

## Guards against taking the same weapon twice.
var picked_up:bool=false

## True for fixed guns: they cannot be picked up, and the model stays upright.
var mounted:bool=false

## Weapon visual built by Kit.weapon().
var model:Node3D

## Godot lifecycle hook: builds the model (lying on its side unless mounted),
## a 22 x 12 x 120 cm pickup collider, and registers it in the shared batch.
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

## Called when the player interacts: swaps the player's weapon with this one
## through game.swap_weapon(). Returns true on success, false if already
## taken or if this is a mounted gun.
func take(player):
	if picked_up or mounted:return false
	game.swap_weapon(self)
	picked_up=true
	collision_layer=0
	queue_free()
	return true
