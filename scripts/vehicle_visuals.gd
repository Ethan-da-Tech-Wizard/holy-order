## Render batching for armoured vehicles (tanks, trucks).
##
## A vehicle is built from dozens of separate box panels, each with its own
## collider so shells can damage individual plates. Drawing every panel as its
## own MeshInstance3D would cost one draw call each; this helper replaces them
## with one MultiMesh per material while leaving the colliders untouched.
## Called by the ardennes and omaha tank/truck builders after the model is
## complete.
extends RefCounted
# Moving vehicles keep individual armor colliders, but draw same-material panels
# together in vehicle-local coordinates. Wheels, ramps and crew keep their motion.

## Merges the visible BoxMesh panels under `root` into one MultiMeshInstance3D
## per shared material, hides the originals, and links damageable panels to
## their batch slot so damage can recolour or shrink the right instance.
## [param root] vehicle root; the batch is added as its child so it moves with it.
## [param excluded] nodes (or ancestors) that must stay separate, such as
## wheels, ramps and crew that animate independently.
## Side effects: sets meta "batched_panels" (count) on root and "vehicle_panel_batch"
## on each batch node; writes render_batch/render_index/render_origin on panel
## bodies that expose `integrity` and `damage_at`.
static func batch_boxes(root:Node3D,excluded:Array=[]):
	# Group candidate panels by material instance id: instances in one
	# MultiMesh must share a material, so this is the natural partition.
	var groups={}
	for visual in root.find_children("*","MeshInstance3D",true,false):
		if not visual.mesh is BoxMesh or not visual.visible or visual.is_queued_for_deletion():continue
		var skip=false
		for node in excluded:
			if node==visual or node.is_ancestor_of(visual):skip=true
		if skip or visual.material_override==null:continue
		var key=visual.material_override.get_instance_id()
		if not groups.has(key):groups[key]=[]
		groups[key].append(visual)

	# A group of one gains nothing from batching, so it is left alone (below).
	var count=0
	for key in groups:
		var visuals=groups[key]
		if visuals.size()<2:continue

		# Unit cube scaled per instance through each transform, so one mesh
		# serves boxes of every size; vertex colours allow per-panel tinting
		# (used for damage) on top of the shared albedo.
		var mesh=BoxMesh.new()
		mesh.size=Vector3.ONE
		mesh.material=visuals[0].material_override.duplicate()
		if mesh.material is StandardMaterial3D:mesh.material.vertex_color_use_as_albedo=true
		var batch=MultiMeshInstance3D.new()
		batch.multimesh=MultiMesh.new()
		batch.multimesh.transform_format=MultiMesh.TRANSFORM_3D
		batch.multimesh.use_colors=true
		batch.multimesh.mesh=mesh
		batch.multimesh.instance_count=visuals.size()
		batch.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(batch)
		batch.set_meta("vehicle_panel_batch",true)
		for i in range(visuals.size()):
			var visual=visuals[i]

			# Transform of the panel relative to the vehicle root (not the world),
			# so the batch stays correct as the vehicle moves; the panel size is
			# baked into the basis as scale because the shared mesh is 1x1x1.
			var xf=root.global_transform.affine_inverse()*visual.global_transform*Transform3D(Basis.IDENTITY.scaled(visual.mesh.size),Vector3.ZERO)
			batch.multimesh.set_instance_transform(i,xf)
			batch.multimesh.set_instance_color(i,Color.WHITE)
			var body=visual.get_parent()

			# Damageable panel: it needs to know where its instance lives so
			# later damage updates the correct MultiMesh slot.
			if body.get("integrity")!=null and body.has_method("damage_at"):
				body.refresh_bounds()
				body.render_batch=batch.multimesh
				body.render_index=i
				body.render_origin=xf.origin

			# Hide (not free) the original: its collider and node identity are
			# still used by the damage and hit-testing code.
			visual.hide()
			count+=1
	root.set_meta("batched_panels",count)
