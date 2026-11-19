# ==============================================================================
# Program: view_smoothing.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for view_smoothing.gd.
# ==============================================================================
extends RefCounted
# The body uses fixed-step interpolation; mouse look and viewmodel animation stay
# on render frames. Only interpolate the eye position, never the mouse rotation.
static func restore(player):
	if not is_instance_valid(player.camera):return
	player.camera.position-=player.camera_render_offset
	player.camera_render_offset=Vector3.ZERO
static func display(player):
	var head=player.head
	var offset=head.global_basis.inverse()*(head.get_global_transform_interpolated().origin-head.global_position)
	player.camera.position+=offset
	player.camera_render_offset=offset
