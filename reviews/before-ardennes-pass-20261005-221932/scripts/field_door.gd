# ==============================================================================
# Program: field_door.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for field_door.gd.
# ==============================================================================
## A swinging wooden door that can be opened, closed and destroyed.
##
## Spawned by the village/battle builders. The player's interaction code finds it
## through the "field_door" group and calls `use()` when the player presses the use
## key at `interaction_position()`. The door leaf is a destructible solid from
## art.gd; if bullets or explosions destroy it, it stops being usable.
## After each open/close the battle world is told geometry changed so AI
## navigation can re-plan through the new gap.
extends Node3D

const Art=preload("res://scripts/art.gd")

# The door panel (a breakable solid built in _ready); null until the node enters the tree.
var leaf

# Logical state: true while the door is swung open (or opening).
var opened: bool=false

# True during the swing tween; blocks re-triggering mid-animation.
var moving: bool=false

# Yaw at spawn, so the open angle is relative to however the builder rotated the door.
var base_angle: float=0

# Leaf width in metres; the hinge is at the node origin and the leaf extends along +x.
var width: float=1.72

## Build the leaf, its two cross-braces and the handle, and register in the door group.
func _ready():
	add_to_group("field_door")
	# Capture the placed yaw before any animation changes it.
	base_angle=rotation.y
	# Offset the leaf by half its width so the node origin acts as the hinge edge.
	leaf=Art.solid(self,Vector3(width,2.18,0.10),Vector3(width/2,1.09,0),Art.material(Color("514937")),0,"wood")
	# Two horizontal braces (low and high) sit on the leaf's back face to read as planks.
	for y in [0.45,1.55]:
		Art.box(leaf,Vector3(width-0.05,0.10,0.035),Vector3(0,y-1.09,-0.065),Art.material(Color("3c3e36"),0.5))
	# Knob near the free edge, away from the hinge.
	Art.sphere(leaf,0.035,Vector3(width/2-0.15,0.02,-0.087),Art.material(Color("6e6650"),0.7))
	# If the leaf is shot to pieces mid-swing, drop the 'moving' lock so state never sticks.
	leaf.geometry_changed.connect(func():
		if leaf.destroyed: moving=false
	)

## Whether the door can still be used.
## @return false when the leaf was freed or destroyed.
func available() -> bool:
	return is_instance_valid(leaf) and not leaf.destroyed

## Toggle the door open/closed with a short swing animation.
##
## Ignored while already moving or after destruction. Side effects: flips `opened`,
## tweens `rotation:y`, and notifies the battle world once the swing finishes.
func use():
	if moving or not available():return
	# Flip target state immediately so a second press cannot start a contradictory tween.
	opened=not opened
	moving=true
	var tween=create_tween()
	# Open swings -1.63 rad (about 93 degrees) so the door clears the frame; 0.42 s sine ease feels weighty.
	tween.tween_property(self,"rotation:y",base_angle+(-1.63 if opened else 0.0),0.42).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		# Release the lock, then tell the battle world to rebuild navigation around the new opening.
		moving=false
		# The world registers itself in "battle_world"; absent in isolated tests, hence the empty check.
		var worlds=get_tree().get_nodes_in_group("battle_world")
		if not worlds.is_empty():worlds[0].geometry_updated(global_position)
	)

## Point the player should be near to use the door.
## @return World position of the leaf's middle at roughly hand height (1 m).
func interaction_position() -> Vector3:
	return to_global(Vector3(width/2,1.0,0))
