#include "AnimationGraphWorkspaceRouter.h"
#include "AnimationGraphUIStateStore.h"

namespace {
AnimationGraphWorkspacePath &EnsureWorkspacePath(const std::string &graphHandle) {
    return AnimationGraphUIStateStore::WorkspacePathForGraph(graphHandle);
}

bool IsSameWorkspace(const AnimationGraphWorkspaceDescriptor &lhs, const AnimationGraphWorkspaceDescriptor &rhs) {
    return lhs.kind == rhs.kind &&
        lhs.nodeId == rhs.nodeId &&
        lhs.stateId == rhs.stateId &&
        lhs.transitionId == rhs.transitionId;
}
}

namespace AnimationGraphWorkspaceRouter {
AnimationGraphWorkspacePath &GetWorkspacePath(const std::string &graphHandle) {
    return EnsureWorkspacePath(graphHandle);
}

const AnimationGraphWorkspaceDescriptor &GetCurrentWorkspace(const std::string &graphHandle) {
    return EnsureWorkspacePath(graphHandle).items.back();
}

void PushWorkspace(const std::string &graphHandle, const AnimationGraphWorkspaceDescriptor &descriptor) {
    AnimationGraphWorkspacePath &path = EnsureWorkspacePath(graphHandle);
    if (path.items.empty()) {
        path.items.push_back(AnimationGraphWorkspaceDescriptor());
    }

    AnimationGraphWorkspaceDescriptor &current = path.items.back();
    if (IsSameWorkspace(current, descriptor)) {
        return;
    }

    path.items.push_back(descriptor);
}

void PopWorkspace(const std::string &graphHandle) {
    AnimationGraphWorkspacePath &path = EnsureWorkspacePath(graphHandle);
    if (path.items.size() > 1) {
        path.items.pop_back();
    }
}

void TruncateWorkspacePath(const std::string &graphHandle, size_t count) {
    AnimationGraphWorkspacePath &path = EnsureWorkspacePath(graphHandle);
    if (count == 0) {
        path.items.clear();
        path.items.push_back(AnimationGraphWorkspaceDescriptor());
        return;
    }
    if (count < path.items.size()) {
        path.items.resize(count);
    }
    if (path.items.empty()) {
        path.items.push_back(AnimationGraphWorkspaceDescriptor());
    }
}

void ResetWorkspacePathForHandle(const std::string &graphHandle) {
    AnimationGraphWorkspacePath &path = AnimationGraphUIStateStore::WorkspacePathForGraph(graphHandle);
    path.items.clear();
    path.items.push_back(AnimationGraphWorkspaceDescriptor());
}

void ApplyPendingNavigation(const std::string &graphHandle, MCEPanelState::AnimationGraphPanelState &panelState) {
    if (panelState.pendingWorkspaceNavigationKind == MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationNone) {
        return;
    }

    AnimationGraphWorkspaceDescriptor descriptor;
    descriptor.nodeId = panelState.pendingWorkspaceNodeId;
    descriptor.stateId = panelState.pendingWorkspaceStateId;
    descriptor.transitionId = panelState.pendingWorkspaceTransitionId;

    switch (panelState.pendingWorkspaceNavigationKind) {
        case MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationStateMachine:
            descriptor.kind = AnimationGraphWorkspaceKind::StateMachine;
            break;
        case MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationBlendSpace:
            descriptor.kind = AnimationGraphWorkspaceKind::BlendSpace;
            break;
        case MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationStateSubgraph:
            descriptor.kind = AnimationGraphWorkspaceKind::StateSubgraph;
            break;
        default:
            descriptor.kind = AnimationGraphWorkspaceKind::RootGraph;
            break;
    }

    if (descriptor.kind != AnimationGraphWorkspaceKind::RootGraph) {
        PushWorkspace(graphHandle, descriptor);
    }

    panelState.pendingWorkspaceNavigationKind = MCEPanelState::AnimationGraphPanelState::WorkspaceNavigationNone;
    panelState.pendingWorkspaceNodeId.clear();
    panelState.pendingWorkspaceStateId.clear();
    panelState.pendingWorkspaceTransitionId.clear();
}
}
