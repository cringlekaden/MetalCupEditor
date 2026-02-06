# MetalCup Editor

MetalCup Editor is a **macOS application** built on top of the **MetalCup engine framework**.

It provides real-time tooling, inspection, and workflow support for developing scenes, assets, and rendering features using the MetalCup engine.

> **Status:** Active development. Core editor workflows are still being built.

---

## Overview

- macOS app written in Swift
- Links against the MetalCup engine framework
- ImGui is bridged and fully integrated
- Designed as a real-time renderer + editor environment

This repository contains **editor UI, tooling, and workflow systems**.  
All rendering and runtime logic lives in the MetalCup engine framework.

---

## Current Features

### Renderer Tooling
The editor exposes real-time renderer controls via ImGui:

- Bloom controls
  - Blur pass count
  - Intensity
  - Knee / threshold
- Image-Based Lighting (IBL) controls (when an environment is present)
- Exposure
- Gamma
- Tone mapping method
- Debug texture and render target visualization
- Basic profiling and timing information

All settings update live while the renderer is running.

### UI & Integration
- ImGui fully bridged into Swift / Metal
- Editor communicates with the engine via clean interfaces
- Asset handles passed into the engine (no raw file paths)

---

## Asset Workflow

The editor builds on the engine’s automated asset system:

- Asset directories are scanned automatically
- Assets are imported and assigned meta files
- Stable asset handles are generated
- Scenes and entities reference assets by handle
- Designed to support future asset browsing and editing tools

---

## Planned Features

### Editor
- Scene graph window
  - Entity hierarchy
  - Add/remove entities
- Component inspector
  - Add/remove components
  - Edit component properties
- Asset browser
  - Browse imported assets
  - Assign assets to entities
- Editor layout improvements

### Core Systems
- Entity Component System (ECS)
- Scene serialization
- Entity and component persistence
- Asset reference serialization via handles

Serialization is the next major milestone for enabling persistent editor workflows.

---

## Requirements

- macOS 26 (only version tested so far)
- Apple Silicon Mac
- Xcode (recent version recommended)
- MetalCup engine framework
- Swift + Metal

---

## Building & Running

1. Clone the repository: ```git clone https://github.com/cringlekaden/MetalCupEditor.git```
2. Open the project in Xcode
3. Ensure the MetalCup engine framework is available and linked
4. Build & run the macOS app target

---

## Relationship to MetalCup Engine

- This repository contains **no core rendering engine code**
- Rendering, assets, and runtime systems live in the MetalCup framework
- The editor exists purely to drive, inspect, and configure engine state

---

## License

MIT License. Use the code however you like. No warranties.
