## Archived review snapshot (before-unified-performance-20261006): the code below is the script as it stood for that
## review. The documentation was carried over from the live script tests/inspect_api.gd for every
## code line that is unchanged; lines that differ from the live script have no extra notes.
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
