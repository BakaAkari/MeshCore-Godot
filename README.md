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

The Blender exporter converts to the "unity_ref" convention, which matches
Godot's right-handed Y-up space directly (no extra flips needed). Triangles
arrive already wound for the receiver (split normals preserved).

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
