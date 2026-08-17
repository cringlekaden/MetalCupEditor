# Gameplay authoring

## Physics and character controllers

Physics uses the engine’s Jolt integration. Add suitable collider/rigid-body components for physical objects, and a character-controller component for player motion. The controller Lua helpers are available only for a bound entity with that component: `Entity:Move`, `Entity:SetLookInput`, `Entity:Jump`, `Entity:IsGrounded`, and `Entity:GetVelocity`. Tune values in the inspector and test in Play mode; collision setup is still early-development tooling.

## Input and scripting

Scripts are classified from `.lua`, `.mcscript`, or `.cs`, but Lua is the implemented embedded runtime on stable main. A script can declare `onCreate`, `onStart`, and `onUpdate`; access `Time.deltaTime`; log through `Log.Info`, `Log.Warn`, or `Log.Error`; and query input with `Input.IsKeyDown`, `Input.WasKeyPressed`, `Input.GetMouseDelta`, `Input.SetCursorMode`, `Input.GetCursorMode`, and `Input.ToggleCursorModeLocked`. Stable key constants include `Key.W`, `Key.A`, `Key.S`, `Key.D`, `Key.Space`, `Key.LeftShift`, `Key.LeftArrow`, and `Key.RightArrow`.

## Animation and graphs

Animation clips are classified from `.anim`, `.animclip`, and `.mcanim`; graphs use `.mcanimgraph`. Import a supported animated model, ensure an animator component is on the entity, then assign a clip or graph asset through the inspector/content browser. Animation graph editing supports graph assets, parameters, nodes and state transitions, compiled for runtime evaluation. Use graph parameters from Lua via `Entity:GetAnimator():SetFloat`, `SetBool`, and `SetTrigger` when an animator is available. Asset-import combinations and graph UX remain version-sensitive.

## Play mode

Play mode creates a runtime session from the current editor scene and resets runtime input state. It is for testing, not a packaged build. Save authored changes before entering Play; stop the session before treating editor changes as persistent scene edits.
