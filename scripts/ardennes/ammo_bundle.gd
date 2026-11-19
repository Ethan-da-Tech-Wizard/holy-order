## A pile of loose ammunition dropped by a dead soldier, that the player can
## pick up with the interact key.
##
## Role: spawned by the Ardennes/Omaha game scripts when an actor dies; `game`
## is set by the spawner and `contents` holds {kind, rounds} entries. Lives on
## collision layer 32 (pickups), which only the player's interaction ray tests.
extends StaticBody3D
const Art=preload("res://scripts/art.gd")

## The battle controller; used for toast().
var game

## Array of {kind: String, rounds: int}; emptied as the player takes ammunition.
var contents:Array=[]

## Godot lifecycle hook: registers in group "ammo_bundles" (so the interact
## code can find bundles), sets layer 32 / mask 0, and builds a small olive-brown box.
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

## Moves as many rounds as fit into the player's ammunition pack.
## [param player] the player node; its `ammo_pack` decides capacity (24 space units).
## Removes entries emptied by the transfer and frees the bundle when nothing
## is left, so leftovers stay on the ground if the pack is full.
func take(player):
	var total=0
	for item in contents.duplicate():
		var n=player.ammo_pack.add_rounds(item.kind,item.rounds)
		item.rounds-=n
		total+=n
		if item.rounds==0:contents.erase(item)
	if contents.is_empty():queue_free()
	game.toast("Recovered %d rounds. Pack %.1f / 24 space."%[total,player.ammo_pack.space_used()],3)

## Bullets pass through ammunition without effect; the empty body keeps
## projectile code from treating the bundle as an obstacle with a handler missing.
func receive_hit(_amount:float,_point:Vector3):pass
