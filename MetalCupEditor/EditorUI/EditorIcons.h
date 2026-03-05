/// EditorIcons.h
/// Centralized Font Awesome 7 icon definitions and UTF-8 helpers.
/// Uses Font Awesome Free 7 (Solid + Regular) codepoints.

#pragma once

#include "../ImGui/imgui.h"
#include <array>
#include <cstdint>

namespace EditorIcons {
    enum class Id : uint16_t {
        Play = 0,
        Pause,
        Stop,
        Simulate,
        Reset,
        Translate,
        Rotate,
        Scale,
        Select,
        Snap,
        Local,
        World,
        Camera,
        Plus,
        Folder,
        Scene,
        Material,
        Mesh,
        Texture,
        HDRI,
        Info,
        DirectionalLight,
        PointLight,
        SpotLight,
        Warning,
        File,
        Count
    };

    struct Definition {
        Id id;
        const char *name;
        const char *metadataKey;
        ImWchar codepoint;
    };

    inline constexpr Definition kDefinitions[] = {
        { Id::Play, "Play", "play", 0xf04b },
        { Id::Pause, "Pause", "pause", 0xf04c },
        { Id::Stop, "Stop", "stop", 0xf04d },
        { Id::Simulate, "Simulate", "flask", 0xf0c3 },
        { Id::Reset, "Reset", "rotate-left", 0xf2ea },
        { Id::Translate, "Translate", "arrows-up-down-left-right", 0xf047 },
        { Id::Rotate, "Rotate", "rotate", 0xf2f1 },
        { Id::Scale, "Scale", "up-right-and-down-left-from-center", 0xf424 },
        { Id::Select, "Select", "hand-pointer", 0xf245 },
        { Id::Snap, "Snap", "magnet", 0xf076 },
        { Id::Local, "Local", "map-marker-alt", 0xf3c5 },
        { Id::World, "World", "globe", 0xf57d },
        { Id::Camera, "Camera", "camera", 0xf030 },
        { Id::Plus, "Plus", "plus", 0x2b },
        { Id::Folder, "Folder", "folder", 0xf07b },
        { Id::Scene, "Scene", "cubes", 0xf1b3 },
        { Id::Material, "Material", "palette", 0xf53f },
        { Id::Mesh, "Mesh", "cube", 0xf1b2 },
        { Id::Texture, "Texture", "image", 0xf03e },
        { Id::HDRI, "HDRI", "globe", 0xf57d },
        { Id::Info, "Info", "circle-info", 0xf05a },
        { Id::DirectionalLight, "DirectionalLight", "", 0xf185 },
        { Id::PointLight, "PointLight", "", 0xf0eb },
        { Id::SpotLight, "SpotLight", "", 0xf3c5 },
        { Id::Warning, "Warning", "triangle-exclamation", 0xf071 },
        { Id::File, "File", "file", 0xf15b }
    };

    inline int EncodeUtf8(ImWchar codepoint, char out[5]) {
        if (codepoint <= 0x7f) {
            out[0] = static_cast<char>(codepoint);
            out[1] = '\0';
            return 1;
        }
        if (codepoint <= 0x7ff) {
            out[0] = static_cast<char>(0xc0 | ((codepoint >> 6) & 0x1f));
            out[1] = static_cast<char>(0x80 | (codepoint & 0x3f));
            out[2] = '\0';
            return 2;
        }
        if (codepoint <= 0xffff) {
            out[0] = static_cast<char>(0xe0 | ((codepoint >> 12) & 0x0f));
            out[1] = static_cast<char>(0x80 | ((codepoint >> 6) & 0x3f));
            out[2] = static_cast<char>(0x80 | (codepoint & 0x3f));
            out[3] = '\0';
            return 3;
        }
        out[0] = static_cast<char>(0xf0 | ((codepoint >> 18) & 0x07));
        out[1] = static_cast<char>(0x80 | ((codepoint >> 12) & 0x3f));
        out[2] = static_cast<char>(0x80 | ((codepoint >> 6) & 0x3f));
        out[3] = static_cast<char>(0x80 | (codepoint & 0x3f));
        out[4] = '\0';
        return 4;
    }

    inline const Definition &DefinitionFor(Id id) {
        const size_t index = static_cast<size_t>(id);
        return kDefinitions[index];
    }

    inline const char *Name(Id id) {
        return DefinitionFor(id).name;
    }

    inline ImWchar Codepoint(Id id) {
        return DefinitionFor(id).codepoint;
    }

    inline const char *Glyph(Id id) {
        static std::array<std::array<char, 5>, static_cast<size_t>(Id::Count)> glyphs {};
        static bool initialized = false;
        if (!initialized) {
            initialized = true;
            for (const Definition &definition : kDefinitions) {
                const size_t index = static_cast<size_t>(definition.id);
                EncodeUtf8(definition.codepoint, glyphs[index].data());
            }
        }
        return glyphs[static_cast<size_t>(id)].data();
    }
}
