# MeshCore Godot

Godot-side receiver for [MeshCore](https://github.com/BakaAkari/MeshCore) — the
Blender-centric live-link ecosystem. Blender streams scene changes
(transforms, meshes, deletes) over the MeshSync wire protocol (msProtocol 124)
and this addon applies them straight into the edited scene tree.

Pure GDScript (Godot 4.4+): no GDExtension, no native builds.

## Install

Copy `addons/meshcore/` into your project, then enable
**Project → Plugins → MeshCore**. It starts an HTTP server on `0.0.0.0:18080`
while the plugin is active.

## Usage

1. Enable the plugin in Godot; open the scene you want to sync into.
2. In Blender, enable the MeshCore addon and hit **Sync Now** (or auto-sync).
3. Objects appear as `Node3D` hierarchies under the edited scene root,
   with a `MeshInstance3D` child per mesh.

## Coordinates

Blender streams raw Z-up data (scene handedness `RightZUp`, `scale_factor=1`).
This addon converts to Godot's right-handed Y-up -Z-forward space with the same
linear basis change C used by Unity's `FlipYZ_ZUpCorrector`:
- position/normal: `(x, y, z) -> (x, z, -y)`
- quaternion: `(x, y, z, w) -> (x, z, -y, w)` (conjugated by C; NOT `(-x,-z,y,w)`)
- scale: `(x, y, z) -> (x, z, y)`

C is a proper rotation (det +1), so the coordinate change itself adds no
reflection. It does not remove the mesh's winding policy: the importer
**reverses** Blender's CCW polygons into Godot CW front faces (matching Godot's
BoxMesh, which scores 12/12 inward on a centered box cross-dot). Transforms are
written as absolute per-node local values so incremental (transform-only)
updates are idempotent. `handedness`/`scale_factor` are retained for
diagnostics but not runtime-enforced (contract is fixed RightZUp, scale=1).

## Layout

- `addons/meshcore/protocol.gd` — wire decoder (Set/Delete messages)
- `addons/meshcore/server.gd` — minimal HTTP/1.1 server
- `addons/meshcore/importer.gd` — scene-tree application
- `addons/meshcore/plugin.gd` — editor plugin entry
- `tests/` — headless unit + E2E tests (`godot --headless --script tests/...`)

## Status

Working: transforms, full mesh sync (split normals, UV0), deletes,
hierarchy creation. Roadmap: materials, cameras, lights, incremental
sync parity, Godot 4.x physics-shape helpers.
