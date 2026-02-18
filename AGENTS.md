# MetalCup Agent Guide (AGENTS.md)

This repository contains:
- **MetalCupEngine** (Swift framework): rendering + ECS + serialization runtime.
- **MetalCupEditor** (macOS app): ImGui editor + project/asset workflow.
- **ImGui (vendor)**: upstream ImGui sources + official backends only.

This file defines how automated agents (Codex/LLMs) must operate in this codebase.

---

## Where to Find Things (critical paths)
- **Engine runtime (Swift):** `MetalCupEngine/MetalCupEngine/`
- **Editor app (Swift/ObjC++):** `MetalCupEditor/MetalCupEditor/`
- **ImGui + ImGuizmo integration:** `MetalCupEditor/MetalCupEditor/EditorCore/ImGui/` and `MetalCupEditor/MetalCupEditor/EditorUI/`
- **ImGui panels:** `MetalCupEditor/MetalCupEditor/EditorUI/Panels/`
- **Shared ImGui widgets:** `MetalCupEditor/MetalCupEditor/EditorUI/Widgets/`
- **Editor↔Engine bridges:** `MetalCupEditor/MetalCupEditor/EditorCore/Bridge/` and `MetalCupEngine/MetalCupEngine/Bridge/`
- **Engine rendering core:** `MetalCupEngine/MetalCupEngine/Core/` and `MetalCupEngine/MetalCupEngine/Graphics/`
- **Scene + ECS:** `MetalCupEngine/MetalCupEngine/Game/`
- **Project assets (per-project only):** `MetalCupEditor/MetalCupEditor/Projects/<ProjectName>/Assets/`
- **Shaders (per-project assets):**
  - `MetalCupEditor/MetalCupEditor/Projects/<ProjectName>/Assets/Shaders/`
  - Currently any shader changes need to be done in each project's shaders
- **Scenes (per-project assets):** `MetalCupEditor/MetalCupEditor/Projects/<ProjectName>/Assets/Scenes/`
- **Materials (per-project assets):** `MetalCupEditor/MetalCupEditor/Projects/<ProjectName>/Assets/Materials/`

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

## Engine / Editor Architecture Rules (hard requirements)
- **No singletons anywhere** in Engine or Editor (no `static let shared`, no global mutable state, no global service locators).
- **Services must be passed explicitly** (constructor injection or owned by Application/Layer and passed down).
- **Engine must not depend on Editor types.** Editor may depend on Engine.
- **Renderer must not pull state from globals.** It uses only renderer delegate callbacks and explicitly passed frame/context objects.
- **No per-frame logging.** Logs must be event-driven (state change) or error-only.
- **No debug prints in shipping code.** `print`/`NSLog` only behind a compile flag for debug builds.
- **Keep file count stable.** Do not create new subsystems unless required by the pass.

---

## How to Add a New System (ownership + injection)
- **Ownership:** The Application (Engine) or EditorLayer (Editor) owns the system instance.
- **Construction:** Create the system with explicit dependencies in its initializer.
- **Injection:** Pass the system (or its dependencies) down to consumers via initializers or properties.
- **Wiring:** Update the owning layer/app to construct and store the system, then pass it where needed.
- **No globals:** Do not register in a global registry or static accessor.

---

## Singleton Ban Checklist (short)
- No `static let shared` or `static var shared`.
- No global mutable variables or global service locators.
- No hidden singletons via static caches that hold app state.
- Dependencies are passed explicitly through initializers or owners.

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
- Panel functions live in `MetalCupEditor/MetalCupEditor/EditorUI/Panels/`:
  - visibility state (persisted)
  - `onImGuiRender()` or `render()`
  - minimal direct filesystem access (delegate to services)
- Avoid panels owning long-lived engine objects directly.
- Panels interact via editor services:
  - `EditorProjectManager` (project/scene lifecycle)
  - `AssetOps` / `AssetRegistry` (asset operations + metadata)
  - `EditorSelection` (selection state)
  - `EditorLogCenter` (logging)
 - Shared ImGui widgets live in `MetalCupEditor/MetalCupEditor/EditorUI/Widgets/`.

ImGui setup and panel dispatch are centralized in:
- `MetalCupEditor/MetalCupEditor/EditorCore/ImGui/ImGuiBridge.mm`
- `MetalCupEditor/MetalCupEditor/EditorCore/ImGui/ImGuiLayer.swift`
 - If text input breaks, ensure ImGui's `KeyEventResponder` remains in the responder chain (see `ImGuiBridge.mm`).

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
- All asset operations go through a single “source of truth” service (`AssetOps`).
- Asset metadata and lookups live in `AssetRegistry`.
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
- Do not introduce a new project layout.
- Do not add third-party dependencies without explicit approval.
- Do not change serialization formats unless asked.
- NO singletons.
- NO global static shared instances.
- NO static global state.
- All services must be injected explicitly.
- Renderer, Application, and EditorLayer should receive services via constructor or property injection.
