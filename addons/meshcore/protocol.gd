class_name MeshCoreProtocol
## Decoder matching the real MeshSync wire format (msProtocol 124).
## All little-endian; vectors are SharedVector<T>: u32 count + raw items,
## zero-padded to 4-byte alignment.
const PROTOCOL_VERSION := 124
const ENTITY_TRANSFORM := 1
const ENTITY_CAMERA := 2
const ENTITY_LIGHT := 3
const ENTITY_MESH := 4

# TransformDataFlags
const TF_POSITION := 1 << 1
const TF_ROTATION := 1 << 2
const TF_SCALE := 1 << 3
const TF_VISIBILITY := 1 << 4
const TF_LAYER := 1 << 5
const TF_INDEX := 1 << 6
const TF_REFERENCE := 1 << 7

# MeshDataFlagsBit
const MF_REFINE := 1 << 2
const MF_INDICES := 1 << 3
const MF_COUNTS := 1 << 4
const MF_POINTS := 1 << 5
const MF_NORMALS := 1 << 6
const MF_MATERIAL_IDS := 1 << 12
const MF_UV0 := 1 << 24

class Reader:
	var data: PackedByteArray
	var pos := 0
	func _init(d: PackedByteArray) -> void: data = d
	func remaining() -> int: return data.size() - pos
	func ok() -> bool: return pos <= data.size() - 4
	func u32() -> int: var v: int = data.decode_u32(pos); pos += 4; return v
	func i32() -> int: var v: int = data.decode_s32(pos); pos += 4; return v
	func u64() -> int: var v: int = data.decode_u64(pos); pos += 8; return v
	func f32() -> float: var v: float = data.decode_float(pos); pos += 4; return v
	func s() -> String:
		var n := i32()
		var v := data.slice(pos, pos + n).get_string_from_utf8()
		pos += n
		_pad4(n)
		return v
	func v3() -> Vector3: return Vector3(f32(), f32(), f32())
	func quat() -> Quaternion: return Quaternion(f32(), f32(), f32(), f32())
	func shared_f32(ncomp: int) -> PackedFloat32Array:
		var n := u32()
		var a := PackedFloat32Array(); a.resize(n * ncomp)
		for i in a.size(): a[i] = f32()
		_pad4(n * ncomp * 4)
		return a
	func shared_i32() -> PackedInt32Array:
		var n := u32()
		var a := PackedInt32Array(); a.resize(n)
		for i in a.size(): a[i] = i32()
		_pad4(n * 4)
		return a
	func _pad4(bytes_read: int) -> void:
		var rem := bytes_read % 4
		if rem: pos += 4 - rem

class Entity:
	var type: int
	var id := -1
	var host_id := -1
	var path := ""
	var pos := Vector3.ZERO
	var rot := Quaternion.IDENTITY
	var scale := Vector3.ONE
	var visible := true
	var index := 0
	var refine_flags := 0
	var points := PackedFloat32Array()   # xyz triplets, per-vertex
	var normals := PackedFloat32Array()  # xyz triplets, per-index (loop)
	var uv0 := PackedFloat32Array()      # uv pairs, per-index (loop)
	var counts := PackedInt32Array()
	var indices := PackedInt32Array()
	var material_ids := PackedInt32Array()

static func parse_set_body(r: Reader) -> Dictionary:
	## SetMessage body: header + Scene
	r.i32()  # protocol version
	var session_id := r.i32()
	r.i32()  # message_id
	r.u64()  # timestamp
	# Scene
	r.u64()  # validation_hash
	var data_flags := r.u32()
	var scene := {"session_id": session_id, "entities": [] as Array[Entity]}
	if data_flags & 1:  # settings
		r.i32()  # handedness
		r.f32()  # scale_factor
	if data_flags & (1 << 2):  # entities
		var n := r.u32()
		for i in n:
			scene.entities.append(parse_entity(r))
	return scene

static func parse_entity(r: Reader) -> Entity:
	var e := Entity.new()
	e.type = r.i32()
	e.id = r.i32()
	e.host_id = r.i32()
	e.path = r.s()
	# transform flags + body
	var tflags := r.u32()
	if tflags & TF_POSITION: e.pos = r.v3()
	if tflags & TF_ROTATION: e.rot = r.quat()
	if tflags & TF_SCALE: e.scale = r.v3()
	if tflags & TF_VISIBILITY: e.visible = r.u32() != 0
	if tflags & TF_LAYER: r.i32()
	if tflags & TF_INDEX: e.index = r.i32()
	if tflags & TF_REFERENCE: r.s()
	if e.type == ENTITY_MESH:
		_parse_mesh(r, e)
	return e

static func _parse_mesh(r: Reader, e: Entity) -> void:
	var mflags := r.u32()
	if mflags & MF_REFINE:
		e.refine_flags = r.u32()
		r.u32()  # max_bone_influence
		r.f32()  # scale_factor
	if mflags & MF_INDICES: e.indices = r.shared_i32()
	if mflags & MF_COUNTS: e.counts = r.shared_i32()
	if mflags & MF_POINTS: e.points = r.shared_f32(3)
	if mflags & MF_NORMALS: e.normals = r.shared_f32(3)
	if mflags & MF_MATERIAL_IDS: e.material_ids = r.shared_i32()
	if mflags & MF_UV0: e.uv0 = r.shared_f32(2)

static func parse_delete_body(r: Reader) -> Array:
	## DeleteMessage body: header + u32 n + (string + i32 id) * n + u32 + u32
	r.i32(); r.i32(); r.i32(); r.u64()  # header
	var paths: Array = []
	var n := r.u32()
	for i in n:
		paths.append(r.s())
		r.i32()  # id
	return paths

static func decode_set(body: PackedByteArray) -> Dictionary:
	return parse_set_body(Reader.new(body))

static func decode_delete(body: PackedByteArray) -> Array:
	return parse_delete_body(Reader.new(body))
