#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
editor_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
engine_root=$(CDPATH= cd -- "$editor_root/../MetalCupEngine" && pwd)
shader_root="$engine_root/MetalCupEngine/Assets/Shaders"
texture_root="$editor_root/MetalCupEditor/Projects/Sandbox/Assets/Textures"
validation_root="$editor_root/RendererValidation"
icon_root="$editor_root/MetalCupEditor/Resources/Icons"
icon_manifest="$script_dir/EditorIconFonts.sha256"
icon_loader="$editor_root/MetalCupEditor/EditorCore/ImGui/ImGuiBridge.mm"

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

icon_font_count=$(find "$icon_root" -maxdepth 1 -type f -name '*.otf' | wc -l | tr -d ' ')
test "$icon_font_count" = "2"
while read -r expected filename; do
    actual=$(shasum -a 256 "$icon_root/$filename" | awk '{print $1}')
    test "$actual" = "$expected"
done < "$icon_manifest"
test -f "$icon_root/FONT-AWESOME-LICENSE.txt"
test ! -d "$icon_root/metadata"
grep -q 'inDirectory:@"Icons"' "$icon_loader"
grep -q 'ResolveEditorIconFontPath("FA7Free-Regular-400.otf")' "$icon_loader"
grep -q 'ResolveEditorIconFontPath("FA7Free-Solid-900.otf")' "$icon_loader"
grep -q 'AddFontFromFileTTF' "$icon_loader"

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
grep -q 'path = MetalCupEditor/Resources/Icons;' "$pbx"

if git -C "$engine_root" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$engine_root" ls-files --error-unmatch MetalCupEngine/Assets/Shaders/BasicShaders.metal >/dev/null
    git -C "$editor_root" ls-files --error-unmatch RendererValidation/Project.mcp >/dev/null
    git -C "$editor_root" ls-files --error-unmatch ASSET_ATTRIBUTION.md >/dev/null
    git -C "$editor_root" ls-files --error-unmatch MetalCupEditor/Projects/Sandbox/Assets/Textures/Moon/lroc_color_2k.jpg >/dev/null
    git -C "$editor_root" ls-files --error-unmatch MetalCupEditor/Resources/Icons/FA7Free-Regular-400.otf >/dev/null
    git -C "$editor_root" ls-files --error-unmatch MetalCupEditor/Resources/Icons/FA7Free-Solid-900.otf >/dev/null
    git -C "$editor_root" ls-files --error-unmatch MetalCupEditor/Resources/Icons/FONT-AWESOME-LICENSE.txt >/dev/null
fi

if test "$#" -gt 0; then
    app_bundle=$1
    app_resources="$app_bundle/Contents/Resources"
    test -d "$app_resources"
    while read -r expected filename; do
        bundled="$app_resources/Icons/$filename"
        test -f "$bundled"
        actual=$(shasum -a 256 "$bundled" | awk '{print $1}')
        test "$actual" = "$expected"
        bundled_count=$(find "$app_resources" -type f -name "$filename" | wc -l | tr -d ' ')
        test "$bundled_count" = "1"
    done < "$icon_manifest"
    test -f "$app_resources/Icons/FONT-AWESOME-LICENSE.txt"
    test ! -d "$app_resources/Icons/metadata"
    test ! -e "$app_resources/EditorSettings.json"
    test ! -e "$app_resources/imgui.ini"
    test ! -e "$app_resources/Projects"
fi

echo "Stage 4 repository resource verification passed"
