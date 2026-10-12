extends "res://scripts/ardennes/player.gd"
const Wire=preload("res://scripts/omaha/wire.gd")
var last_fired:float=-999

func _ready():
	super._ready()
	ammo_pack.containers.clear()
	set_firearm("garand",8,100)
	ammo_pack.add_rounds("garand",96)
	camera.far=4400

func dismount():
	if truck==null or not truck.arrived:return
	var p=truck.seat_transform(seat).origin
	truck=null
	prone=false
	crouched=false
	global_position=p
	velocity=Vector3(0,-1,-2.5)
	climb_from=p
	climb_to=game.world.on_ground(p+Vector3(0,0,-2.5))+Vector3(0,0.15,0)
	climbing=0.48
	game.toast("MOVE OFF THE RAMP • USE THE OBSTACLES • Z PRONE",6)

func _physics_process(delta):
	super._physics_process(delta)
	if game.phase!="playing" or truck!=null:return
	if position.z>0:
		velocity.x*=0.82
		velocity.z*=0.82
		if position.z>35:
			position.z=35
			game.toast("Deep water • head for the beach",2)

func dig_stroke():
	# Preserve digging; close shovel work can cut one wire segment if every engineer falls.
	if truck!=null or grenade_time>0 or cooldown>0 or not has_shovel:return
	var ray=PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*3.1,1)
	ray.exclude=shot_exclusions()
	var hit=get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.collider is Wire:
		cooldown=0.65
		hit.collider.damage_at(100,hit.position)
		game.sounds.play("clang",-12)
		game.toast("CUTTING WIRE • %d / 16"%int(hit.collider.get_meta("cuts",0)),1)
		return
	super.dig_stroke()
