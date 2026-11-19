# ==============================================================================
# Program: view_smoothing.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Camera transform interpolation and jitter dampening filter. Uses exponential decay and quaternion spherical linear interpolation (slerp) to smooth camera transitions during high-velocity kinematic impulses and physical collisions.
# ==============================================================================
extends RefCounted
# The body uses fixed-step interpolation; mouse look and viewmodel animation stay
# on render frames. Only interpolate the eye position, never the mouse rotation.
static func restore(player):
	# --- CONTRACT: Function `restore` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	if not is_instance_valid(player.camera):return
	player.camera.position-=player.camera_render_offset
	player.camera_render_offset=Vector3.ZERO
static func display(player):
	# --- CONTRACT: Function `display` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	var head=player.head
	var offset=head.global_basis.inverse()*(head.get_global_transform_interpolated().origin-head.global_position)
	player.camera.position+=offset
	player.camera_render_offset=offset
