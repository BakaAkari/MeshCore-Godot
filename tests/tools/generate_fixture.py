"""Generate an offline E2E fixture for the Godot receiver using the ACTUAL
MeshCore Blender exporter + protocol serializer.

Builds an asymmetric rotated mesh (Wedge) under nested nonuniform-scale parents,
plus a negative-scale cube (NegCube) and a 30deg-Z rotated box (Box). Writes an
INDEPENDENT JSON contract derived from Blender's matrix_world (and the C basis
change), NOT from implementation-derived constants, so the Godot E2E test can
compare real world vertices / world normals / transform against Blender ground
truth.

Contract semantics (see test_e2e_fixture.gd):
  - "world_transform"[+]      : expected Godot node world matrix (origin + 3 basis cols)
                                = C @ matrix_world @ C^-1
  - "world_verts"             : C @ matrix_world @ local_vert  (per-vertex set)
  - "blender_world_face_normals"
                              : Blender outward polygon normals in world space
                                (verified CCW/outward via recalc_face_normals)
  - "godot_world_face_normals": C @ blender_world_face_normal  (the direction a
                                NON-reversed import would follow). Because the
                                importer REVERSES Blender CCW -> Godot CW, the
                                Godot triangles' true world normals must be the
                                OPPOSITE of these (dot < 0) on an outward-face mesh.
  - "world_loop_normals"      : C_basis @ inv_transpose(matrix_world) @ normal_local

Running (requires the MeshCore Blender addon package on PYTHONPATH):
  blender --background --factory-startup --python-exit-code 1 \
      --python tests/tools/generate_fixture.py

Output written into tests/fixtures/ (repo-relative lookup is used by the Godot
E2E test, so no /tmp prerequisite).
"""

import json
import math
import os
import sys
from pathlib import Path

# MeshCore package root for the real exporter; override with MESHCORE_ROOT.
_REPO = Path(__file__).resolve().parent.parent.parent
MESHCORE_ROOT = Path(os.environ.get("MESHCORE_ROOT", "/Users/baka_akari/code/MeshCore"))
FIXTURE = _REPO / "tests" / "fixtures"

for p in (MESHCORE_ROOT, MESHCORE_ROOT / "unity_mesh_sync", MESHCORE_ROOT / "tests"):
    p = str(p)
    if p not in sys.path:
        sys.path.insert(0, p)

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

from unity_mesh_sync.blender_exporter import export_scene  # noqa: E402
from unity_mesh_sync.meshsync import protocol as P  # noqa: E402

# Basis change C: Blender (x,y,z) -> Godot (x,z,-y). det = +1 (proper rotation).
C = Matrix(((1, 0, 0), (0, 0, 1), (0, -1, 0)))
C4 = C.to_4x4()


def world_matrix(obj):
    return obj.matrix_world.copy()


def godot_world_transform_json(obj):
    mw = world_matrix(obj)
    gm = C4 @ mw @ C4.inverted()
    return {
        "origin": [round(v, 6) for v in gm.translation],
        "basis_c0": [round(v, 6) for v in gm.col[0][:3]],
        "basis_c1": [round(v, 6) for v in gm.col[1][:3]],
        "basis_c2": [round(v, 6) for v in gm.col[2][:3]],
    }


def godot_world_verts_json(obj):
    mw = world_matrix(obj)
    return [
        [round(v, 6) for v in (C4 @ (mw @ vert.co))[:3]] for vert in obj.data.vertices
    ]


def godot_world_face_normals_json(obj):
    """C-mapped Blender OUTWARD polygon normal (the non-reversed direction)."""
    mw = world_matrix(obj)
    out = []
    for p in obj.data.polygons:
        vs = p.vertices
        if len(vs) < 3:
            continue
        a = C4 @ (mw @ obj.data.vertices[vs[0]].co)
        b = C4 @ (mw @ obj.data.vertices[vs[1]].co)
        c = C4 @ (mw @ obj.data.vertices[vs[2]].co)
        n = (b - a).cross(c - a)
        if n.length == 0:
            continue
        out.append([round(v, 6) for v in n.normalized()])
    return out


def godot_world_loop_normals_json(obj):
    mw = world_matrix(obj)
    inv_t = mw.inverted().transposed()
    c3 = C
    out = []
    for loop in obj.data.loops:
        n = Vector(obj.data.corner_normals[loop.index].vector)
        out.append([round(v, 6) for v in (c3 @ (inv_t @ n)).normalized()])
    return out


def godot_world_tri_normals_json(obj):
    """C-mapped Blender OUTWARD normal for each fan triangle, in the same order
    the importer emits triangles (polygon order, then fan (v0, vk, vk+1)).
    The Godot importer REVERSES each fan to (vk+1, vk, v0) -> CW, so a Godot
    triangle at index i must have a normal OPPOSITE element i here."""
    mw = world_matrix(obj)
    co = obj.data.vertices
    out = []
    for p in obj.data.polygons:
        vs = p.vertices
        c = len(vs)
        if c < 3:
            continue
        for k in range(c - 2):
            a = C4 @ (mw @ co[vs[0]].co)
            b = C4 @ (mw @ co[vs[k + 1]].co)
            cc = C4 @ (mw @ co[vs[k + 2]].co)
            n = (b - a).cross(cc - a)
            out.append([round(v, 6) for v in n.normalized()])
    return out


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)

    # hierarchy: Root (nonuniform scale+rot) / Arm (nested nonuniform) / Wedge
    bpy.ops.object.empty_add(type="PLAIN_AXES", location=(1.5, -2.0, 0.5))
    root = bpy.context.active_object
    root.name = "Root"
    root.rotation_euler = Euler((math.radians(35), 0, math.radians(-20)), "XYZ")
    root.scale = (2.0, 1.0, 0.5)

    bpy.ops.object.empty_add(type="PLAIN_AXES")
    arm = bpy.context.active_object
    arm.name = "Arm"
    arm.parent = root
    arm.rotation_euler = Euler(
        (math.radians(-15), math.radians(40), math.radians(25)), "XYZ"
    )
    arm.scale = (0.5, 3.0, 1.0)
    arm.location = (0.25, 0.0, -0.1)

    # asymmetric wedge mesh (object-local), intentionally non-symmetric
    mesh = bpy.data.meshes.new("Wedge")
    bm = bmesh.new()
    verts = [
        bm.verts.new((0, 0, 0)),
        bm.verts.new((2.0, 0, 0)),
        bm.verts.new((0.4, 1.6, 0)),
        bm.verts.new((0, 0, 1.1)),
        bm.verts.new((2.0, 0, 0.9)),
        bm.verts.new((0.4, 1.6, 1.3)),
    ]
    bm.faces.new((verts[0], verts[1], verts[2]))
    bm.faces.new((verts[0], verts[3], verts[4], verts[1]))
    bm.faces.new((verts[1], verts[4], verts[5], verts[2]))
    bm.faces.new((verts[2], verts[5], verts[3], verts[0]))
    bm.faces.new((verts[3], verts[5], verts[4]))
    # ensure genuinely OUTWARD / CCW polygon normals (Blender front-face rule)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    wed = bpy.data.objects.new("Wedge", mesh)
    bpy.context.collection.objects.link(wed)
    wed.parent = arm
    wed.rotation_euler = Euler(
        (math.radians(10), math.radians(-30), math.radians(60)), "XYZ"
    )
    wed.scale = (1.6, 0.8, 1.2)
    wed.location = (0.1, 0.2, 0.0)
    mesh.update()

    # negative-scale edge case
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(4.0, 0.0, 0.0))
    neg = bpy.context.active_object
    neg.name = "NegCube"
    neg.scale = (1.0, -1.0, 1.0)

    # axis-aligned box rotated 30deg about Z (winding reference)
    bpy.ops.mesh.primitive_cube_add(size=2.0, location=(-3.0, 1.0, 0.5))
    box = bpy.context.active_object
    box.name = "Box"
    box.rotation_euler = Euler((0, 0, math.radians(30)), "XYZ")

    bpy.context.view_layer.update()

    scene = export_scene(bpy.context)
    data = P.SetMessage(scene, session_id=777).serialize()
    FIXTURE.mkdir(parents=True, exist_ok=True)
    (FIXTURE / "scene.bin").write_bytes(data)

    targets = {
        "Wedge": {
            "world_transform": godot_world_transform_json(wed),
            "world_verts": godot_world_verts_json(wed),
            "world_face_normals": godot_world_face_normals_json(wed),
            "world_tri_normals": godot_world_tri_normals_json(wed),
            "world_loop_normals": godot_world_loop_normals_json(wed),
        },
        "NegCube": {
            "world_transform": godot_world_transform_json(neg),
            "world_verts": godot_world_verts_json(neg),
            "world_face_normals": godot_world_face_normals_json(neg),
            "world_tri_normals": godot_world_tri_normals_json(neg),
        },
        "Box": {
            "world_transform": godot_world_transform_json(box),
            "world_verts": godot_world_verts_json(box),
            "world_face_normals": godot_world_face_normals_json(box),
            "world_tri_normals": godot_world_tri_normals_json(box),
        },
    }
    env = {"paths": [e.path for e in scene.entities], "entities": []}
    for e in scene.entities:
        rec = {"path": e.path, "type": type(e).__name__}
        if hasattr(e, "position"):
            rec["position"] = [round(x, 6) for x in e.position]
            rec["rotation"] = [round(x, 6) for x in e.rotation]
            rec["scale"] = [round(x, 6) for x in e.scale]
        if hasattr(e, "points") and len(e.points):
            rec["points"] = [round(float(x), 6) for x in e.points]
            rec["normals"] = [round(float(x), 6) for x in e.normals]
            rec["indices"] = [int(x) for x in e.indices]
            rec["counts"] = [int(x) for x in e.counts]
        env["entities"].append(rec)

    (FIXTURE / "contract.json").write_text(
        json.dumps({"targets": targets, "env": env}, indent=2)
    )

    # incremental subset (only the Wedge leaf changed -> ancestors as bare transforms)
    inc = export_scene(bpy.context, only_paths={"/Root/Arm/Wedge"})
    (FIXTURE / "incremental.bin").write_bytes(
        P.SetMessage(inc, session_id=778).serialize()
    )

    print(
        "[FIXTURE] wrote scene.bin (%d bytes), contract.json, incremental.bin"
        % len(data)
    )
    print("[FIXTURE] entities:", [e.path for e in scene.entities])
    print(
        "[FIXTURE] Wedge verts=%d loops=%d polys=%d"
        % (len(wed.data.vertices), len(wed.data.loops), len(wed.data.polygons))
    )


if __name__ == "__main__":
    main()
