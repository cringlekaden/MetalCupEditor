# MetalCup Agent Guide (AGENTS.md)

This repository contains:
- **MetalCupEngine** (Swift framework): rendering + ECS + serialization runtime.
- **MetalCupEditor** (macOS app): ImGui editor + project/asset workflow.
- **ImGui Bridge** (ObjC++/C++): editor UI panels and backend glue (Metal + macOS input).

This file defines how automated agents (Codex/LLMs) must operate in this codebase.

---

## Golden Rules

### 1) Keep scope tight
- Only change what the prompt asks.
- If you discover extra issues, **log them** (EditorLogCenter) and mention them in the final summary, but do not fix them unless requested.

### 2) Prefer deletion over complexity
- Remove dead code and duplicate systems rather than wrapping them.
- Avoid introducing new layers/managers unless replacing something being removed.

### 3) Do not move project structure unless explicitly requested

If anything is “shared assets” or legacy migration: **do not reintroduce**. Keep per-project only.

### 4) Minimize file churn
- Prefer modifying existing files.
- Avoid creating many new files for small refactors.
- If a new file is necessary, keep it small and justify it in the summary.

### 5) ImGui style consistency
- Target “Hazel-like” ImGui: clean, minimal, consistent spacing.
- Avoid default ImGui bright blues; keep theme cohesive.
- Ensure labels align and no clipping occurs.
- Must look professional AAA quality for all new elements and panels and features.
- Create abstracted helpers to generate ImGui elements to avoid duplicated boilerplate everywhere.

### 6) No runtime regressions
- Must compile and run.
- Keep behavior stable unless the prompt explicitly changes it.
- Avoid touching rendering/shader paths unless asked.

---

## Build / Run Expectations

- Editor builds and runs from Xcode.
- Engine is a framework dependency of the Editor.
- ImGui is integrated via C++ sources + ObjC++ bridge + Swift call surface.

If you change public API visibility across modules:
- Prefer adding explicit `public` only where needed.
- Avoid widening API surface unnecessarily.

---

## Logging (required)
- Use **EditorLogCenter** for all editor logs.
- Do not add new “status center” or duplicate logging systems.
- Log file ops: create/rename/delete/duplicate/import.
- Log project open/close/save and scene save/load.

---

## ImGui Panel Architecture (preferred)
Panels should follow a consistent pattern:
- `Panel` class encapsulates:
  - visibility state (persisted)
  - `onImGuiRender()` or `render()`
  - minimal direct filesystem access (delegate to services)
- Avoid panels owning long-lived engine objects directly.
- Panels interact via a small set of editor services (ProjectService, AssetService, SelectionService, EditorLogCenter).

---

## Editor State Persistence
Persist:
- Visible panels
- Docking layout (if supported; otherwise minimal panel visibility)
- Selected entity and current content browser directory
- Open/closed state of collapsible headers (if already implemented)

Store under: current canonical editor state location.

---

## Filesystem / Assets
- All asset operations go through a single “source of truth” service.
- Avoid multiple competing path utilities.
- Canonicalize all paths (no `/Assets/Assets/...`).

When fixing path issues:
- Prefer a small targeted migration with clear logging.
- Never delete user data silently.

---

## How Agents Should Respond
At the end of a change:
- List files modified.
- Summarize behavior changes.
- Note any migrations performed.
- Mention any discovered issues not fixed.

---

## What NOT to do
- Do not rewrite the renderer.
- Do not redesign ECS.
- Do not introduce a new project layout.
- Do not add third-party dependencies without explicit approval.
- Do not change serialization formats unless asked.

---

## Quick Glossary
- **Project**: top-level container (assets + scenes + settings).
- **Scene**: serialized ECS world.
- **Material**: serialized `.mcmat` document editable via material editor window.
- **Asset handle/UUID**: internal stable identity; must not be exposed as the primary UX for selection.
