# First playable project

This tutorial uses only stable-main authoring: an empty scene, entities/components, a character controller, Lua input, and Play mode. It does not require a model import.

1. Launch the editor and choose **File > New Project**. Keep the default location or choose another writable folder; name it `FirstPlayable`. The editor creates `FirstPlayable/Project.mcp`, `Assets/Scenes/Default.mcscene`, and its working folders.
2. Open `Assets/Scenes/Default.mcscene` in the content browser. In the scene hierarchy, create an entity named `Player` and use the inspector to give it a transform above the origin.
3. Add the character-controller component in the inspector. Add a camera component to `Player` (or make a separate camera entity) and position it so the scene is visible. Add a light if the default scene is dark.
4. Create `Assets/Scripts/Player.lua` in the content browser and attach the script component to `Player`. The asset system recognizes `.lua` as a script. Use this API-verified starting point:

```lua
function onUpdate()
  if Input.IsKeyDown(Key.W) then Entity:Move({ x = 0, z = 1 }) end
  if Input.WasKeyPressed(Key.Space) then Entity:Jump() end
end
```

`onCreate`, `onStart`, and `onUpdate` are optional lifecycle callbacks. `Input`, `Key`, `Time.deltaTime`, `Log`, and the bound `Entity` table are supplied by the Lua bridge. Movement only has controller behavior when the entity has a character controller.
5. Save the scene, then enter Play mode. Click the viewport if needed so it receives input. Use W to move and Space to request a jump. Stop Play mode before editing scene content again.

This verifies the current playable loop but is not an export workflow: stable main does not package a standalone game.
