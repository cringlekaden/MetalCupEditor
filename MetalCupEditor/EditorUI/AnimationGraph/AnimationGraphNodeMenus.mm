#include "AnimationGraphNodeCanvas.h"

#include <unordered_map>
#include <unordered_set>

namespace AnimationGraphNodeMenus {

void DrawCanvasContextMenus(void *context,
                            AnimationGraphSnapshot &snapshot,
                            const std::unordered_map<std::string, AnimationGraphNodeRecord *> &nodeById,
                            std::unordered_set<std::string> &selectedNodeIds,
                            MCEPanelState::AnimationGraphPanelState &panelState) {
    (void)context;
    (void)snapshot;
    (void)nodeById;
    (void)selectedNodeIds;
    (void)panelState;
}

void DrawAddNodePopup(void *context,
                      AnimationGraphSnapshot &snapshot,
                      std::unordered_set<std::string> &selectedNodeIds,
                      MCEPanelState::AnimationGraphPanelState &panelState) {
    (void)context;
    (void)snapshot;
    (void)selectedNodeIds;
    (void)panelState;
}

} // namespace AnimationGraphNodeMenus
