// EditorIcons.h
// Centralized Font Awesome 7 icon definitions and UTF-8 helpers.
// Uses Font Awesome Free 7 (Solid + Regular) codepoints.

#pragma once

#include "../../ImGui/imgui.h"
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
        Warning,
        File,
        Count
    };

    struct Definition {
        Id id;
        const char *name;
        ImWchar codepoint;
    };

    inline constexpr Definition kDefinitions[] = {
        { Id::Play, "Play", 0xf04b },
        { Id::Pause, "Pause", 0xf04c },
        { Id::Stop, "Stop", 0xf04d },
        { Id::Simulate, "Simulate", 0xf0c3 },
        { Id::Reset, "Reset", 0xf2ea },
        { Id::Translate, "Translate", 0xf047 },
        { Id::Rotate, "Rotate", 0xf2f1 },
        { Id::Scale, "Scale", 0xf424 },
        { Id::Select, "Select", 0xf245 },
        { Id::Snap, "Snap", 0xf890 },
        { Id::Local, "Local", 0xf3c5 },
        { Id::World, "World", 0xf57d },
        { Id::Camera, "Camera", 0xf030 },
        { Id::Plus, "Plus", 0x2b },
        { Id::Folder, "Folder", 0xf07b },
        { Id::Scene, "Scene", 0xf5fd },
        { Id::Material, "Material", 0xf5a1 },
        { Id::Mesh, "Mesh", 0xf1b2 },
        { Id::Texture, "Texture", 0xf03e },
        { Id::HDRI, "HDRI", 0xf57d },
        { Id::Warning, "Warning", 0xf071 },
        { Id::File, "File", 0xf15b }
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

