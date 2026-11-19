## Archived review snapshot (before-town-armor-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script scripts/view_smoothing.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
## Camera display smoothing helpers for the first-person player.
##
## Problem solved: physics runs at 20-30 Hz (see graphics.gd) but the screen
## renders at up to 60 fps, so a camera glued to the physics body would stutter.
## Godot can interpolate the body's transform between ticks; these two helpers
## apply that interpolation to the camera position only. Mouse rotation is
## never interpolated because it is already updated every render frame and
## smoothing it would add input lag.
##
## Usage by player.gd: _process calls restore() first and display() last;
## _physics_process calls restore() first, so physics code always sees the
## true, un-offset camera position.
extends RefCounted
# The body uses fixed-step interpolation; mouse look and viewmodel animation stay
# on render frames. Only interpolate the eye position, never the mouse rotation.

## Removes the render-time offset applied by display().
## [param player] the player node; needs `camera`, `camera_render_offset`.
## Safe to call when the camera is already freed or no offset is applied.
## Without it the offset would accumulate every frame.
static func restore(player):
	if not is_instance_valid(player.camera):return
	player.camera.position-=player.camera_render_offset
	player.camera_render_offset=Vector3.ZERO

## Shifts the camera from the physics-tick position to the interpolated
## position for this render frame.
## [param player] needs `head` (Node3D) and `camera`; stores the applied
## offset in `player.camera_render_offset` so restore() can undo it.
static func display(player):
	var head=player.head

	# Convert the world-space difference between the interpolated and the raw
	# head position into head-local space (inverse basis) because camera.position
	# is local to its parent.
	var offset=head.global_basis.inverse()*(head.get_global_transform_interpolated().origin-head.global_position)
	player.camera.position+=offset
	player.camera_render_offset=offset
