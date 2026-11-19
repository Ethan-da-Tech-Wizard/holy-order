## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/field_door.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## A hinged, destructible wooden door for village houses (desert mission).
##
## Built by village.gd inside each house's front doorway. The door pivots about
## this node's origin (the hinge); the visual leaf is a Breakable solid
## offset by half the door width. Player and AI call use() to swing it open or
## shut; after the swing the world is told geometry changed so the AI
## navigation reopens or closes the passage (World.geometry_updated).
## If the leaf is destroyed it can no longer move.
extends Node3D

const Art=preload("res://scripts/art.gd")

## The Breakable body forming the door slab; null-safe checks via available().
var leaf

## True while the door is swung open.
var opened: bool=false

## True during the open/close tween; blocks re-entrant use() calls.
var moving: bool=false

## Closed-door yaw in radians (set from the placement rotation in _ready).
var base_angle: float=0

## Door slab width in metres (1.72, just under the 1.8 m doorway gap so it
## does not clip the frame).
var width: float=1.72

## Godot lifecycle hook: builds the slab, two cross-braces and a handle knob.
func _ready():
	add_to_group("field_door")
	base_angle=rotation.y

	# Slab is offset by half its width so the hinge sits at the node origin.
	leaf=Art.solid(self,Vector3(width,2.18,0.10),Vector3(width/2,1.09,0),Art.material(Color("514937")),0,"wood")
	for y in [0.45,1.55]:
		Art.box(leaf,Vector3(width-0.05,0.10,0.035),Vector3(0,y-1.09,-0.065),Art.material(Color("3c3e36"),0.5))
	Art.sphere(leaf,0.035,Vector3(width/2-0.15,0.02,-0.087),Art.material(Color("6e6650"),0.7))

	# If the door is shot to pieces mid-swing, stop treating it as moving.
	leaf.geometry_changed.connect(func():
		if leaf.destroyed: moving=false
	)

## True if the door still exists and has not been destroyed. Callers check
## this before offering the "open door" prompt.
func available() -> bool:
	return is_instance_valid(leaf) and not leaf.destroyed

## Toggles the door: swings it 1.63 rad (about 93 degrees) outward over 0.42 s.
## Ignored while already moving or destroyed. When the swing finishes it
## notifies the battle world so pathfinding sees the new opening.
func use():
	if moving or not available():return
	opened=not opened
	moving=true

	# Sine easing makes the door accelerate and settle like a real hinge.
	var tween=create_tween()
	tween.tween_property(self,"rotation:y",base_angle+(-1.63 if opened else 0.0),0.42).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func():
		moving=false

		# Group lookup because the door does not hold a reference to the world.
		var worlds=get_tree().get_nodes_in_group("battle_world")
		if not worlds.is_empty():worlds[0].geometry_updated(global_position)
	)

## World position of the door's centre at hand height, used as the target of
## the interact prompt (game.gd) and for AI path checks (world.gd).
func interaction_position() -> Vector3:
	return to_global(Vector3(width/2,1.0,0))
