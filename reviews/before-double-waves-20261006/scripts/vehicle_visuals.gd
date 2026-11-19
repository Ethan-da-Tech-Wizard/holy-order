# ==============================================================================
# Program: vehicle_visuals.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Core Holy Order game component managing state, rendering, kinematics, or sound for vehicle_visuals.gd.
# ==============================================================================
## Draw-call reduction for moving vehicles.
##
## A truck or boat is made of many small box meshes. This helper merges all boxes
## sharing a material into one MultiMeshInstance3D in the vehicle's local space,
## so the vehicle still moves as one unit but costs one draw call per material.
## Called once after a vehicle is built. Armour panels keep their own colliders,
## and panels that track damage are linked to their MultiMesh slot so destroying
## one hides just that instance (see armored_panel.gd / armor.gd).
extends RefCounted

# Moving vehicles keep individual armor colliders, but draw same-material panels
# together in vehicle-local coordinates. Wheels, ramps and crew keep their motion.
# Moving vehicles keep individual armor colliders, but draw same-material panels
# together in vehicle-local coordinates. Wheels, ramps and crew keep their motion.
## Batch all plain box meshes under `root` by material.
##
## @param root Vehicle root node; receives the batch nodes as children and a
##   "batched_panels" meta with the number of merged boxes.
## @param excluded Nodes (and their descendants) that must keep their own meshes,
##   such as wheels and ramps that animate separately.
static func batch_boxes(root:Node3D,excluded:Array=[]):
	# material instance id -> list of box visuals using that material.
	var groups={}
	for visual in root.find_children("*","MeshInstance3D",true,false):
		# Only visible, live BoxMesh nodes with an explicit material are batchable.
		if not visual.mesh is BoxMesh or not visual.visible or visual.is_queued_for_deletion():continue
		# Exclusion covers the node itself and any descendant of an excluded node.
		var skip=false
		for node in excluded:
			if node==visual or node.is_ancestor_of(visual):skip=true
		if skip or visual.material_override==null:continue
		# Group by the material instance, not its colour, so merged boxes look identical.
		var key=visual.material_override.get_instance_id()
		if not groups.has(key):groups[key]=[]
		groups[key].append(visual)
	# Count of boxes merged, stored on the root for tests and the performance overlay.
	var count=0
	for key in groups:
		var visuals=groups[key]
		# A group of one gains nothing from batching.
		if visuals.size()<2:continue
		# A unit cube; each instance is scaled to its box size via its transform.
		var mesh=BoxMesh.new()
		mesh.size=Vector3.ONE
		mesh.material=visuals[0].material_override.duplicate()
		# Per-instance colours let damaged panels be tinted later; they multiply the albedo.
		if mesh.material is StandardMaterial3D:mesh.material.vertex_color_use_as_albedo=true
		var batch=MultiMeshInstance3D.new()
		batch.multimesh=MultiMesh.new()
		batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		batch.multimesh.use_colors=true
		batch.multimesh.mesh=mesh
		batch.multimesh.instance_count=visuals.size()
		# Shadows are skipped on batched panels to save the extra depth pass.
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(batch)
		batch.set_meta("vehicle_panel_batch",true)
		for i in range(visuals.size()):
			var visual=visuals[i]
			# Transform = vehicle-local pose of the original box, times a scale by that box's size
			# (the batch mesh is a unit cube).
			var xf=root.global_transform.affine_inverse()*visual.global_transform*Transform3D(Basis.IDENTITY.scaled(visual.mesh.size),Vector3.ZERO)
			batch.multimesh.set_instance_transform(i,xf)
			batch.multimesh.set_instance_color(i,Color.WHITE)
			# If the box belongs to a damage-tracking armour panel, hand it its MultiMesh slot so
			# destruction can hide only that instance.
			var body=visual.get_parent()
			if body.get("integrity")!=null and body.has_method("damage_at"):
				body.refresh_bounds()
				body.render_batch=batch.multimesh
				body.render_index=i
				body.render_origin=xf.origin
			# Hide the original mesh; the collider on its parent body is untouched.
			visual.hide()
			count+=1
	root.set_meta("batched_panels",count)
