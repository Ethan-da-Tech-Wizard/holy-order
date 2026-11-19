# ==============================================================================
# Program: inspect_api.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Automated test script verifying runtime performance, physics stability, or behavior correctness for inspect_api.gd.
# ==============================================================================
extends SceneTree
func _initialize():
 for key in ClassDB.class_get_integer_constant_list("Environment"):
  if "REFLECT" in key: print(key)
 quit()
