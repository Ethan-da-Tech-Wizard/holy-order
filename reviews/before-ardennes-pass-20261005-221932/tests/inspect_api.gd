# ==============================================================================
# Program: inspect_api.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 18, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for inspect_api.gd.
# ==============================================================================
extends SceneTree
func _initialize():
 for key in ClassDB.class_get_integer_constant_list("Environment"):
  if "REFLECT" in key: print(key)
 quit()
