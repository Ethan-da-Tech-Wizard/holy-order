extends SceneTree
func _initialize():
 for key in ClassDB.class_get_integer_constant_list("Environment"):
  if "REFLECT" in key: print(key)
 quit()
