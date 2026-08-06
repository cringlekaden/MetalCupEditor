#include "AnimationGraphEditorDrafts.h"
#include "AnimationGraphUIStateStore.h"

AnimationGraphEditorDrafts &GetAnimationGraphEditorDrafts() {
    return AnimationGraphUIStateStore::EditorDrafts();
}
