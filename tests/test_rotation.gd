extends SceneTree
## E2E rotation probe: import the rotated wedge from rotation_probe.py and
## verify the node transform matches the expected Godot Y-up conversion.
var server := MeshCoreServer.new()
var importer := MeshCoreImporter.new()
var root3d := Node3D.new()
var phase := 0

func _init() -> void:
	root.add_child(root3d)
	server.entities_received.connect(_on_entities)
	if server.start() != OK:
		quit(1)
		return
	print("[PROBE] server up, waiting for Blender push...")
	var t := 0
	while t < 120000 and phase == 0:
		server.poll()
		OS.delay_msec(8)
		t += 8
	if phase == 0:
		print("[PROBE] TIMEOUT")
		quit(1)
		return
	quit(0)

func _on_entities(entities: Array) -> void:
	importer.apply_entities(entities, root3d)
	var n := root3d.get_node_or_null("Wedge")
	if n == null:
		print("[PROBE] node missing"); quit(1); return
	print("[PROBE] node pos=", n.position, " quat=", n.quaternion, " scale=", n.scale)
	# Expected: Blender (1, 2, 3) -> Godot (1, 3, -2)
	var exp_pos := Vector3(1.0, 3.0, -2.0)
	if n.position.distance_to(exp_pos) > 0.001:
		print("[PROBE] FAIL pos expected=", exp_pos, " got=", n.position)
		quit(1)
		return
	# Expected: Blender 30deg about Z -> Godot 30deg about Y
	# Blender quat (x=0, y=0, z=0.2588, w=0.9659) mapped by C -> (x, z, -y, w)
	# = (0, 0.2588, 0, 0.9659) [NOT (-x,-z,y,w); that is a different rotation]
	var exp_quat := Quaternion(0.0, 0.2588, 0.0, 0.9659)
	if n.quaternion.dot(exp_quat) < 0.999:
		print("[PROBE] FAIL quat expected=", exp_quat, " got=", n.quaternion)
		quit(1)
		return
	# Expected: scale (1, 2, 1) -> (1, 1, 2)
	var exp_scale := Vector3(1.0, 1.0, 2.0)
	if n.scale.distance_to(exp_scale) > 0.001:
		print("[PROBE] FAIL scale expected=", exp_scale, " got=", n.scale)
		quit(1)
		return
	print("[PROBE] PASS rotation/position/scale")
	phase = 1
