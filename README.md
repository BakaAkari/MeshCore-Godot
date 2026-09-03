# MeshCore-Godot — Godot receiver for the MeshCore live link (planned)

The Godot-side receiver of the **MeshCore** ecosystem: will run a server
inside the Godot editor (default port **18080**) and apply the scene streamed
from the MeshCore Blender addon.

## Status: planned — not yet implemented

## Design sketch

- Wire protocol: MeshSync-compatible binary v124 (shared with MeshCore-Unity;
  the Blender addon emits one protocol for all engines)
- Language: **C#** (GDScript is too slow for bulk float-array parsing)
- HTTP: minimal POST handler over `TcpListener` (the client sends plain
  `POST /set|/delete|/fence` with binary bodies)
- Coordinate mapping: Godot is right-handed Y-up — **no winding flip needed**
  (unlike Unity's FLIP_FACES path); only a Blender Z-up → Y-up axis rotation
- Scene apply: SetMessage → `Node3D` hierarchy + `ArrayMesh`;
  DeleteMessage → node removal; SceneBegin/SceneEnd fence gating
  (same session model as the Unity receiver)

## Companion repositories

- **MeshCore** — the Blender addon (core of the ecosystem)
- **MeshCore-Unity** — reference receiver implementation
