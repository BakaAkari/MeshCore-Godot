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

# CameraDataFlags (C++ bitfield bits)
const CF_IS_ORTHO := 1 << 1
const CF_FOV := 1 << 2
const CF_NEAR := 1 << 3
const CF_FAR := 1 << 4
const CF_FOCAL := 1 << 5
const CF_SENSOR := 1 << 6
const CF_LENS_SHIFT := 1 << 7
const CF_VIEW := 1 << 8
const CF_PROJ := 1 << 9
const CF_LAYER_MASK := 1 << 10

# LightDataFlags (C++ bitfield bits)
const LF_LIGHT_TYPE := 1 << 1
const LF_SHADOW_TYPE := 1 << 2
const LF_COLOR := 1 << 3
const LF_INTENSITY := 1 << 4
const LF_RANGE := 1 << 5
const LF_SPOT_ANGLE := 1 << 6
const LF_LAYER_MASK := 1 << 7

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
	scene["handedness"] = 0
	scene["scale_factor"] = 1.0
	if data_flags & 1:  # settings
		# Scene settings were previously discarded. We now retain the two
		# fields (handedness + scale_factor) in the parsed dict for diagnostics,
		# but they are NOT enforced at runtime: the only supported wire contract
		# is RightZUp (handedness=3) with scale_factor=1.0 (the Blender exporter
		# hardcodes both), and the importer's fixed Z-up->Y-up basis change is
		# the handling of RightZUp. A scale_factor of 1.0 has no effect, so it
		# cannot cause double conversion; non-1.0 scaling is outside the current
		# contract and is intentionally left for a future pass.
		scene["handedness"] = r.i32()  # handedness
		scene["scale_factor"] = r.f32()  # scale_factor
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
	elif e.type == ENTITY_CAMERA:
		_parse_camera(r, e)
	elif e.type == ENTITY_LIGHT:
		_parse_light(r, e)
	return e

## Camera: Transform body + CameraDataFlags-gated fields. We don't apply
## camera data in Godot yet, but we MUST consume the bytes or the stream
## desyncs and every following entity fails to decode (the variant_call
## p_offset errors seen in the editor).
static func _parse_camera(r: Reader, _e: Entity) -> void:
	var cd := r.u32()
	r.u32()  # is_ortho (bool, always present)
	if cd & CF_FOV: r.f32()
	if cd & CF_NEAR: r.f32()
	if cd & CF_FAR: r.f32()
	if cd & CF_FOCAL: r.f32()
	if cd & CF_SENSOR: r.f32(); r.f32()
	if cd & CF_LENS_SHIFT: r.f32(); r.f32()
	if cd & CF_VIEW:
		for i in 16: r.f32()
	if cd & CF_PROJ:
		for i in 16: r.f32()
	if cd & CF_LAYER_MASK: r.u32()

## Light: Transform body + LightDataFlags-gated fields. Same consume-only
## rationale as camera.
static func _parse_light(r: Reader, _e: Entity) -> void:
	var ld := r.u32()
	if ld & LF_LIGHT_TYPE: r.i32()
	if ld & LF_SHADOW_TYPE: r.i32()
	if ld & LF_COLOR:
		for i in 4: r.f32()
	if ld & LF_INTENSITY: r.f32()
	if ld & LF_RANGE: r.f32()
	if ld & LF_SPOT_ANGLE: r.f32()
	if ld & LF_LAYER_MASK: r.u32()

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
