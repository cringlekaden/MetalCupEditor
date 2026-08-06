#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
editor_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
engine_root=$(CDPATH= cd -- "$editor_root/../MetalCupEngine" && pwd)
shader_root="$engine_root/MetalCupEngine/Assets/Shaders"
texture_root="$editor_root/MetalCupEditor/Projects/Sandbox/Assets/Textures"
validation_root="$editor_root/RendererValidation"

shader_count=$(find "$shader_root" -maxdepth 1 -type f -name '*.metal' | wc -l | tr -d ' ')
test "$shader_count" = "11"

while read -r expected filename; do
    actual=$(shasum -a 256 "$shader_root/$filename" | awk '{print $1}')
    test "$actual" = "$expected"
done < "$script_dir/CanonicalShaders.sha256"

find "$shader_root" -maxdepth 1 -type f -name '*.metal' -print | while read -r shader; do
    filename=$(basename "$shader")
    grep -q "  $filename$" "$script_dir/CanonicalShaders.sha256"
done

texture_count=$(find "$texture_root" -type f | wc -l | tr -d ' ')
test "$texture_count" = "18"

test -f "$validation_root/Project.mcp"
test -f "$validation_root/Assets/Scenes/RendererValidation.mcscene"
test ! -d "$validation_root/Assets/Shaders"
jq empty "$validation_root/Project.mcp"
jq empty "$validation_root/Assets/Scenes/RendererValidation.mcscene"

pbx="$editor_root/MetalCupEditor.xcodeproj/project.pbxproj"
if grep -q 'Library/Application Support/MetalCupEditor' "$pbx"; then
    echo "Editor project still references live Application Support content." >&2
    exit 1
fi
grep -q 'path = MetalCupEditor/Projects/Sandbox/Assets/Textures;' "$pbx"

if git -C "$engine_root" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$engine_root" ls-files --error-unmatch MetalCupEngine/Assets/Shaders/BasicShaders.metal >/dev/null
    git -C "$editor_root" ls-files --error-unmatch RendererValidation/Project.mcp >/dev/null
    git -C "$editor_root" ls-files --error-unmatch ASSET_ATTRIBUTION.md >/dev/null
    git -C "$editor_root" ls-files --error-unmatch MetalCupEditor/Projects/Sandbox/Assets/Textures/Moon/lroc_color_2k.jpg >/dev/null
fi

echo "Stage 4 repository resource verification passed"
