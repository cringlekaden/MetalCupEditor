#include "AnimationGraphEditorDrafts.h"

AnimationGraphEditorDrafts &GetAnimationGraphEditorDrafts() {
    static AnimationGraphEditorDrafts drafts;
    return drafts;
}

