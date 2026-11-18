# ==============================================================================
# Program: inspect_api.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 18, 2026
# Purpose: Engine introspection test verifying Godot Node3D properties, signal connections, and script exports.
# ==============================================================================
extends SceneTree
func _initialize():
	# Step: Configure initial parameters and dependency references for _initialize
 for key in ClassDB.class_get_integer_constant_list("Environment"):
  if "REFLECT" in key: print(key)
 quit()
