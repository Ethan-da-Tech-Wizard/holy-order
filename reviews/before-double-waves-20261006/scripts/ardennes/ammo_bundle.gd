# ==============================================================================
# Program: ammo_bundle.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for ammo_bundle.gd.
# ==============================================================================
## Dropped bundle of ammunition that the player can pick up.
##
## Spawned (e.g. from a dead soldier or crate) with `contents`, an array of
## dictionaries/objects each having `kind` and `rounds`. The player's use action
## calls `take(player)`, which moves as many rounds as fit into the player's ammo
## pack and removes the bundle once empty. `game` must be set by the spawner for the toast message.
extends StaticBody3D
const Art=preload("res://scripts/art.gd")

# Game controller, used only to show pickup toasts.
var game

# Remaining stacks; each item has `.kind` (ammo type) and `.rounds` (count left).
var contents:Array=[]

## Join the pickup group, set physics layer and build the visible crate with a matching collision box.
func _ready():
	add_to_group("ammo_bundles")
	# Layer 32 is the pickup layer so the player's interaction ray finds bundles; mask 0 since it never collides actively.
	collision_layer=32
	collision_mask=0
	Art.beveled_box(self,Vector3(0.40,0.25,0.32),Vector3.ZERO,Art.material(Color("786a4a")),0.04)
	var cs=CollisionShape3D.new()
	var box=BoxShape3D.new()
	box.size=Vector3(0.40,0.25,0.32)
	cs.shape=box
	add_child(cs)

## Move rounds into the player's pack.
## @param player Player with an `ammo_pack` (add_rounds / space_used).
func take(player):
	var total=0
	# Iterate over a copy because empty stacks are erased from the real array in the loop.
	for item in contents.duplicate():
		# The pack returns how many rounds actually fit, so a full pack leaves the rest in the bundle.
		var n=player.ammo_pack.add_rounds(item.kind,item.rounds)
		item.rounds-=n
		total+=n
		# Remove fully collected stacks; partially taken ones stay for later.
		if item.rounds==0:contents.erase(item)
	# Nothing left: delete the bundle from the world.
	if contents.is_empty():queue_free()
	game.toast("Recovered %d rounds. Pack %.1f / 24 space."%[total,player.ammo_pack.space_used()],3)

## Bundles are not damageable; this satisfies the shared hit interface.
func receive_hit(_amount:float,_point:Vector3):pass
