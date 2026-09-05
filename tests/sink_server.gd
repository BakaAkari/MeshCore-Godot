extends SceneTree
## Long-lived receiver for multi-sync probes. MeshCoreServer is a
## RefCounted with a manual poll() — drive it from _process directly.
var s

func _initialize():
	var Server = load("res://addons/meshcore/server.gd")
	s = Server.new()
	s.start()
	s.entities_received.connect(func(entities):
		print("[sink] entities x%d" % entities.size())
	)
	s.deletes_received.connect(func(paths):
		print("[sink] deletes x%d" % paths.size())
	)
	print("[sink] up")

func _process(_delta):
	if s:
		s.poll()
	return false  # keep running
