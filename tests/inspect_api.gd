## Developer probe, not a test: prints every Environment constant whose name
## contains "REFLECT" so one can check which reflection options this Godot
## version offers.
## Run: godot --headless --path <repo> --script res://tests/inspect_api.gd
extends SceneTree

## SceneTree entry point: list the matching constants, then exit immediately.
func _initialize():
 for key in ClassDB.class_get_integer_constant_list("Environment"):
  if "REFLECT" in key: print(key)
 quit()
