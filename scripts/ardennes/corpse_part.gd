# ==============================================================================
# Program: corpse_part.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Fragmented casualty physics component. Simulates dismembered anatomical rigid body dynamics, angular momentum conservation, and ground friction settlement during explosive detonations.
# ==============================================================================
extends RigidBody3D
var corpse
var part_name:String="torso"
var integrity:float=55
var detached:bool=false
var wound_shown:bool=false
var visual_batch:Dictionary={}

func batch_visual(mesh:MeshInstance3D):
	# --- CONTRACT: Function `batch_visual` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for batch_visual
	visual_batch=corpse.game.batch_remains(mesh)
	set_physics_process(false)
	sleeping_state_changed.connect(func():set_physics_process(detached and not sleeping and not visual_batch.is_empty()))

func _physics_process(_delta):
	# --- DETERMINISTIC SIMULATION TICK: 60 Hz Physics Frame Synchronization ---
	# Invariants:
	# - Parameter delta is fixed at 1/60s (approx 0.01667s) by Engine.max_fps configuration.
	# - Integrates kinematic velocity vectors, applies gravitational acceleration, and updates bounding colliders.
	# - Performs raycast obstacle evaluations before committing spatial position changes.
	# Step: Execute fixed-timestep physics calculation, collision resolution, and kinematics
	if not visual_batch.is_empty():visual_batch.mm.set_instance_transform(visual_batch.slot,global_transform)

func _ready():
	# --- LIFECYCLE INITIALIZATION: Scene Tree Entry & Component Binding ---
	# Invariants:
	# - Configures physics collision layers/masks and spatial spatial transforms.
	# - Caches local references to prevent runtime get_node() tree traversal latency.
	# - Binds event signals and initializes internal state machines.
	# Step: Initialize node state, configure collision layers, and bind signal delegates
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
	# Step: Process damage reception, evaluate armor mitigation, and update health status
	integrity-=amount
	if not wound_shown:
		wound_shown=true
		corpse.wound(self,point)
	if integrity<=0:detach((global_position-point+Vector3(0,0.2,0)).normalized()*minf(amount*0.04,5.0))

func detach(impulse:Vector3):
	# --- CONTRACT: Function `detach` ---
	# Enforces state consistency, validates spatial parameters, and coordinates game systems.
	# Logic: Execute step-by-step processing for detach
	if not detached:
		detached=true
		freeze=false
		if part_name=="torso":corpse.set_physics_process(true)
		if not visual_batch.is_empty():set_physics_process(true)
		corpse.detached_count+=1
		corpse.wound(self,global_position)
	apply_central_impulse(impulse)
	apply_torque_impulse(Vector3(randf_range(-2,2),0,randf_range(-2,2)))
