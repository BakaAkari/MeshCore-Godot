extends SceneTree
## Unit test: build a real SetMessage with the Python wire encoder, decode
## it with the Godot decoder, and compare all fields.
const PY_SCENE := "/tmp/meshcore_godot_fixture.bin"

func _init() -> void:
	var f := FileAccess.open(PY_SCENE, FileAccess.READ)
	if f == null:
		printerr("fixture missing: ", PY_SCENE)
		quit(1)
		return
	var body := f.get_buffer(f.get_length())
	var scene := MeshCoreProtocol.decode_set(body)
	var entities: Array = scene.entities
	assert(entities.size() == 2)
	var cube = entities[0]
	assert(cube.path == "/Cube", cube.path)
	assert(cube.type == MeshCoreProtocol.ENTITY_MESH)
	assert(cube.points.size() == 8 * 3)
	assert(cube.counts.size() == 6)
	assert(cube.indices.size() == 24)
	assert(abs(cube.pos.x - 1.0) < 0.001 and abs(cube.pos.z + 3.0) < 0.001)
	assert(cube.normals.size() == 24 * 3)
	assert(cube.uv0.size() == 24 * 2)
	var empty = entities[1]
	assert(empty.path == "/Empty" and empty.type == MeshCoreProtocol.ENTITY_TRANSFORM)
	print("PASS: python->godot set round-trip (%d entities)" % entities.size())
	quit(0)
