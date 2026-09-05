extends SceneTree
## Compare our Blender-imported mesh against Godot's BoxMesh using the SAME
## geometric test. Ground truth: BoxMesh. If our import scores differently,
## our winding/normals are wrong for Godot.
## For a CENTERED convex box, cross(x)dot(faceOUTWARD) is a valid sign test:
## Godot's BoxMesh is wound CW for front faces, so its face normal points
## opposite the outward centroid direction -> it scores 12/12 inward. That is
## the CORRECT, EXPECTED Godot result, not an artifact. Our import deliberately
## reverses Blender's CCW polygons into Godot CW, so it must reproduce the same
## 12/12 inward score (do NOT "fix" it to 12/12 outward).

var server := MeshCoreServer.new()
var importer := MeshCoreImporter.new()
var root3d := Node3D.new()
var phase := 0
var sent_paths := ["/Cube"]

func _face_normal(v0: Vector3, v1: Vector3, v2: Vector3) -> Vector3:
	return (v1 - v0).cross(v2 - v0).normalized()

func _score(arr: ArrayMesh, label: String) -> int:
	var surf := arr.surface_get_arrays(0)
	var verts: PackedVector3Array = surf[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = surf[Mesh.ARRAY_INDEX] if surf[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var bad := 0
	var total := 0
	var count := idx.size() if idx.size() > 0 else verts.size()
	for t in range(0, count, 3):
		var i0 := idx[t] if idx.size() > 0 else t
		var i1 := idx[t+1] if idx.size() > 0 else t+1
		var i2 := idx[t+2] if idx.size() > 0 else t+2
		var fn := _face_normal(verts[i0], verts[i1], verts[i2])
		var centroid := (verts[i0] + verts[i1] + verts[i2]) / 3.0
		var outward := centroid.normalized()  # cube centered at origin
		total += 1
		if fn.dot(outward) < 0.0:
			bad += 1
	print("[SCORE] %s: %d/%d inward-facing (same formula for all)" % [label, bad, total])
	return bad

func _init() -> void:
	root.add_child(root3d)
	# ground truth first
	var cm: BoxMesh = BoxMesh.new()
	var arr := ArrayMesh.new()
	arr.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, cm.get_mesh_arrays())
	var box_score := _score(arr, "BoxMesh ground truth")

	server.entities_received.connect(_on_entities)
	if server.start() != OK:
		quit(1)
		return
	print("[PROBE] server up, waiting for Blender push...")
	var t := 0
	while t < 60000 and phase == 0:
		server.poll()
		OS.delay_msec(8)
		t += 8
	if phase == 0:
		print("[PROBE] TIMEOUT waiting for push")
		quit(1)
		return
	# our import must reproduce EXACTLY the BoxMesh ground-truth score (no flip)
	if import_score != box_score:
		print("[PROBE] FAIL winding: import=%d != BoxMesh=%d (should match)" % [import_score, box_score])
		quit(1)
		return
	print("[PROBE] PASS winding: import score == BoxMesh ground truth")
	quit(0)

var import_score := -99

func _on_entities(entities: Array) -> void:
	importer.apply_entities(entities, root3d)
	var n := root3d.get_node_or_null("Cube")
	if n == null:
		print("[PROBE] node missing"); quit(1); return
	var mi := n.get_node_or_null("Mesh")
	if mi == null or mi.mesh == null:
		print("[PROBE] mesh missing"); quit(1); return
	import_score = _score(mi.mesh, "Blender-imported cube")
	phase = 1
