# ==============================================================================
# Program: view_smoothing.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for view_smoothing.gd.
# ==============================================================================
## Camera smoothing helper for the first-person player.
##
## Physics runs at a fixed tick, so the player body only moves in steps. Rendering
## happens at the display rate, so without help the camera visibly stutters. This
## helper offsets the camera by the engine's physics-interpolated head position
## each rendered frame, and removes that offset again before the next physics step.
## Used by the player script as `restore(self)` at the start of physics and
## `display(self)` before drawing; the player must expose `camera`, `head` and
## `camera_render_offset` (a Vector3 that remembers the last applied offset).
extends RefCounted

# Design note: only the eye position is interpolated. Mouse look is applied on
# render frames already, and interpolating it would add input lag.
# The body uses fixed-step interpolation; mouse look and viewmodel animation stay
# on render frames. Only interpolate the eye position, never the mouse rotation.
## Undo the render-frame offset so physics code sees the camera's true position.
##
## @param player The player node; mutates `camera.position` and clears `camera_render_offset`.
static func restore(player):
	# The camera can be freed mid-scene change; bail out instead of touching a dead node.
	if not is_instance_valid(player.camera):return
	# Subtract exactly what display() added last frame, otherwise the offset would accumulate.
	player.camera.position-=player.camera_render_offset
	player.camera_render_offset=Vector3.ZERO

## Shift the camera to the interpolated head position for this rendered frame.
##
## @param player The player node; mutates `camera.position` and stores the offset in `camera_render_offset`.
static func display(player):
	var head=player.head
	# Interpolated minus physics position, converted into the head's local space because
	# the camera is a child of the head (its `position` is local, not global).
	var offset=head.global_basis.inverse()*(head.get_global_transform_interpolated().origin-head.global_position)
	# Remember the amount so restore() can subtract it before the next physics step.
	player.camera.position+=offset
	player.camera_render_offset=offset
