# Recovery & Cleanup Report

## Finalized Directory Structure
- Application Support/MetalCupEditor/
  - Projects/
    - <ProjectName>/
      - Project.mcp
      - Assets/ (only asset root)
      - Scenes/
      - Cache/
      - Intermediate/
      - Saved/

## Source-of-Truth Path API
- `EditorFileSystem` (MetalCupEditor/MetalCupEditor/Project/EditorFileSystem.swift)
  - Resolves App Support root, Projects root
  - Resolves bundle resource root (folder reference)
  - Provides editor settings, ImGui config, and default-assets template URL

## What Was Broken and Fixed
- Fixed missing build symbols (legacy project init + scene path normalization).
- Removed shared-assets root assumptions and UI.
- Asset registry now watches only the active project’s Assets folder.
- Added default asset seeding from the bundled template (Projects/Sandbox/Assets).

## Asset ID Policy
- Default assets are copied with their .meta files intact, so handles are stable across new projects.

## No-Project Behavior
- Editor boots with an empty scene when no project is open.
- Startup sanity check logs active project + assets root.

## Sanity Test (manual)
1) Delete a project’s `Assets/` folder -> open project -> defaults are re-seeded.
2) Create new project -> `Assets/` contains default content.
3) Content Browser shows assets; drag/drop materials still works.
