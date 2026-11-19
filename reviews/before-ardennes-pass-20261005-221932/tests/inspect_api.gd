# ==============================================================================
# Program: inspect_api.gd
# Programmer: Ethan-da-Tech-Wizard
# Last Modified: November 19, 2026
# Purpose: Ardennes theater component implementing gameplay mechanics, simulation physics, or AI routines for inspect_api.gd.
# ==============================================================================
## One-off developer utility: lists the Environment constants whose names contain "REFLECT".
##
## Used to check which reflection-related enums the installed Godot version exposes before
## writing environment settings. Prints names and quits; asserts nothing.
## Run: `godot --headless --path . --script res://tests/inspect_api.gd`.
extends SceneTree
func _initialize():
 # ClassDB reflection: all integer constants declared by the Environment class.
 for key in ClassDB.class_get_integer_constant_list("Environment"):
  if "REFLECT" in key: print(key)
 quit()
