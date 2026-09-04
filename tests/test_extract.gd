extends SceneTree
func _init():
	var U = load("res://addons/meshcore/updater.gd")
	var dest := "/tmp/mc_extract_test"
	var msg = U._extract_zip("/tmp/mc015.zip", dest)
	assert(msg == "", "extract failed: " + str(msg))
	assert(FileAccess.file_exists(dest + "/addons/meshcore/plugin.gd"))
	assert(FileAccess.file_exists(dest + "/addons/meshcore/updater.gd"))
	print("EXTRACT PASS")
	quit()
