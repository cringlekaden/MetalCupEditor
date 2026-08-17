# Projects, scenes and content

## Where projects live

The default creation folder is `/Volumes/External/kadencringle/Library/Application Support/MetalCupEditor`. This is for user-created projects, not either source repository. The editor creates a named project folder containing `Project.mcp`, `Assets/`, `Cache/`, `Intermediate/`, and `Saved/`; its initial scene is `Assets/Scenes/Default.mcscene`.

Projects can be opened in place through a selected `.mcp` file. Copy or move the entire project folder, not only `Project.mcp`; then open the moved `Project.mcp`. For version control, commit `Project.mcp`, source assets and `.mcscene`/`.mcmat`/other authored asset files with their metadata. Ignore `Cache`, `Intermediate`, `Saved`, and editor/Xcode derived state. Do not copy personal content from Application Support into either repository.

## Directory model

`Assets/` is project-local. The editor initially creates `Materials`, `Textures`, `Meshes`, `Environments`, `Prefabs`, and `Scenes`; imports and other asset types may also use `Scripts`, `Skeletons`, `Animations`, `AnimationGraphs`, and `Audio`. The repository-owned `RendererValidation/` and `MetalCupEditor/Projects/Sandbox/` are validation/example content, not a user project template. Canonical engine resources belong to MetalCupEngine. Project `Assets/Shaders` is only used after explicitly selecting a project shader override; default projects use canonical engine shaders.

## Scenes, entities and components

Use the content browser to create/open a `.mcscene`, the scene hierarchy to create/select entities, and the inspector to add components and edit transform position, Euler rotation and scale. Saving writes scene data through the engine serializer. Avoid manual edits to serialized files unless you understand the current schema; it is not a stable interchange format.

## Import and materials

The content browser classifies PNG/JPG/JPEG/TGA/BMP/TIF/TIFF textures; HDR/EXR environments; OBJ/USDZ/FBX/glTF/GLB/`.mcmesh` models; `.mcmat` materials; and the extensions listed in [gameplay](gameplay.md). Import/copy source assets into the appropriate project folder and use the browser/inspector to assign their registered handles. Create a material asset (`.mcmat`) and assign its base color, normal, metallic/roughness, AO and emissive inputs where available. Materials use metal/roughness PBR with scalar fallbacks.

## Cameras, lighting, sky and saving

Add a camera component to control the scene view; renderer settings are scene/runtime settings in the renderer panel. Add analytic lights and enable/configure shadows there. Environment assets and the sky/fog/cloud controls are available, as are IBL/rebuild-oriented reflection probes. Save the scene and project after changes. Continuous probe scheduling and physical day/night agreement are not stable features.
