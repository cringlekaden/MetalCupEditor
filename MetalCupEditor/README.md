# MetalCup Editor

A macOS editor for the MetalCup engine, built with ImGui and Metal. It handles projects, assets, scenes, and editor tooling while the engine handles rendering and runtime systems.

## Current Features
- Project creation/open/save with recent project list.
- Scene load/save + play/pause/stop workflow.
- Scene Hierarchy and Inspector for entity/component editing.
- Content Browser for asset management (create/rename/duplicate/delete).
- Renderer panel for bloom/tonemap/IBL settings.
- Viewport with drag-and-drop asset spawning.
- Material editor with texture assignment and PBR controls.
- Profiling and Logs panels.

## How to Use
- Create or open a project from the startup modal (or File > New/Open Project).
- Open or save scenes from File > Open Scene / Save Scene / Save Scene As.
- Create entities in the Scene Hierarchy panel (right-click for create menus).
- Select an entity to edit its components in the Inspector panel.
- Use the Content Browser to manage assets.
- Press Scene > Play to run, Pause to freeze updates, and Stop to return to the editor scene.

## Architecture
- The editor is the UI/tooling layer; the engine provides rendering, ECS, and serialization.
- `EditorCore` owns editor services, ImGui initialization, and bridges into the engine.
- `EditorUI` contains panels and shared ImGui widgets.
- `ImGui/` is vendor-only: upstream ImGui + official backends.
- Asset operations flow through `AssetOps` + `AssetRegistry`.

See `ARCHITECTURE.md` at the repository root for the full structure and data flow.
