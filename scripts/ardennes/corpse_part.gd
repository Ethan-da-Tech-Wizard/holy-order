extends RigidBody3D
var corpse
var part_name:String="torso"
var integrity:float=55
var detached:bool=false
var wound_shown:bool=false
var visual_batch:Dictionary={}

func batch_visual(mesh:MeshInstance3D):
	visual_batch=corpse.game.batch_remains(mesh)
	set_physics_process(false)
	sleeping_state_changed.connect(func():set_physics_process(detached and not sleeping and not visual_batch.is_empty()))

func _physics_process(_delta):
	if not visual_batch.is_empty():visual_batch.mm.set_instance_transform(visual_batch.slot,global_transform)

func _ready():
	set_physics_process(false)
	collision_layer=32
	collision_mask=1
	freeze=true
	freeze_mode=RigidBody3D.FREEZE_MODE_STATIC
	mass=8
	linear_damp=0.45
	angular_damp=1.5
	can_sleep=true

func receive_hit(amount:float,point:Vector3):
	integrity-=amount
	if not wound_shown:
		wound_shown=true
		corpse.wound(self,point)
	if integrity<=0:detach((global_position-point+Vector3(0,0.2,0)).normalized()*minf(amount*0.04,5.0))

func detach(impulse:Vector3):
	if not detached:
		detached=true
		freeze=false
		if part_name=="torso":corpse.set_physics_process(true)
		if not visual_batch.is_empty():set_physics_process(true)
		corpse.detached_count+=1
		corpse.wound(self,global_position)
	apply_central_impulse(impulse)
	apply_torque_impulse(Vector3(randf_range(-2,2),0,randf_range(-2,2)))
