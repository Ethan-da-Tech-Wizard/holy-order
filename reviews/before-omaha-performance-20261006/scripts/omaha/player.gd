# ==============================================================================
# Program: player.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Omaha beach landing component implementing assault physics, tactical coordinates, or telemetry for player.gd.
# ==============================================================================
## Omaha variant of the player: garand rifle loadout, wading, ramp exit and wire cutting.
##
## Extends the Ardennes player, reusing all movement, shooting and inventory code and
## overriding only what differs on the beach: starting weapon, leaving the landing craft,
## water speed limits and shovel use on barbed wire.
extends "res://scripts/ardennes/player.gd"

# Barbed wire class, so the shovel check can recognise wire hit by the ray.
const Wire=preload("res://scripts/omaha/wire.gd")

# Timestamp of the last shot (seconds); -999 means never fired.
var last_fired:float=-999

## Set up the Omaha loadout after the base class has built the player.
func _ready():
	# Run the Ardennes setup first (camera, inventory, input).
	super._ready()
	# Replace the Ardennes starting ammo with an M1 Garand: 8 in the rifle and 96 spare rounds.
	ammo_pack.containers.clear()
	set_firearm("garand",8,100)
	ammo_pack.add_rounds("garand",96)
	camera.far=4400

## Leave the landing craft once it has beached.
## Side effects: clears the truck/seat, sets velocity and starts a short climb over the ramp.
func dismount():
	# Only possible after the boat arrived; otherwise ignore the key.
	if truck==null or not truck.arrived:return
	var p=truck.seat_transform(seat).origin
	truck=null
	# Stand up so the player does not leave the boat prone or crouched.
	prone=false
	crouched=false
	global_position=p
	# Small forward-and-down velocity so the player steps off the ramp instead of floating.
	velocity=Vector3(0,-1,-2.5)
	# The climb helper moves the player from the seat to ground level over `climbing` seconds.
	climb_from=p
	climb_to=game.world.on_ground(p+Vector3(0,0,-2.5))+Vector3(0,0.15,0)
	climbing=0.48
	game.toast("MOVE OFF THE RAMP • USE THE OBSTACLES • Z PRONE",6)

## Run base physics, then limit speed in the surf.
## @param delta Seconds since the previous physics tick.
func _physics_process(delta):
	super._physics_process(delta)
	# Only apply beach rules during play and while on foot.
	if game.phase!="playing" or truck!=null:return
	# z > 0 is the sea side of the beach (waterline at z = 0).
	if position.z>0:
		velocity.x*=0.82
		velocity.z*=0.82
		# Invisible wall in deep water so the player cannot swim away from the fight.
		if position.z>35:
			position.z=35
			game.toast("Deep water • head for the beach",2)

## Swing the shovel; cuts barbed wire when aimed at it, otherwise digs as usual.
func dig_stroke():
	# Preserve digging; close shovel work can cut one wire segment if every engineer falls.
	# Preserve digging; close shovel work can cut one wire segment if every engineer falls.
	if truck!=null or grenade_time>0 or cooldown>0 or not has_shovel:return
	# Ray 3.1 m ahead of the camera; mask 1 is the world/props layer.
	var ray=PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3.1,1)
	ray.exclude=shot_exclusions()
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	# One strike deals 100 damage to the wire; the 0.65 s cooldown paces the cutting.
	if not hit.is_empty() and hit.collider is Wire:
		cooldown=0.65
		hit.collider.damage_at(100,hit.position)
		game.sounds.play("clang",-12)
		# The wire object counts cuts in meta; 16 cuts are shown as the full goal.
		game.toast("CUTTING WIRE • %d / 16"%int(hit.collider.get_meta("cuts",0)),1)
		return
	# No wire in reach: normal digging behaviour.
	super.dig_stroke()
