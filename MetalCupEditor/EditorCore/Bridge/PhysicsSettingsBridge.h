/// PhysicsSettingsBridge.h
/// Defines the physics settings bridge for the editor UI.
/// Created by Kaden Cringle

#pragma once

#include <stdint.h>
#include "MCEBridgeMacros.h"

#ifdef __cplusplus
extern "C" {
#endif

uint32_t MCEPhysicsGetEnabled(MCE_CTX);
void MCEPhysicsSetEnabled(MCE_CTX, uint32_t value);

void MCEPhysicsGetGravity(MCE_CTX, float *x, float *y, float *z);
void MCEPhysicsSetGravity(MCE_CTX, float x, float y, float z);

uint32_t MCEPhysicsGetSolverIterations(MCE_CTX);
void MCEPhysicsSetSolverIterations(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetQualityPreset(MCE_CTX);
void MCEPhysicsSetQualityPreset(MCE_CTX, uint32_t value);

float MCEPhysicsGetFixedDeltaTime(MCE_CTX);
void MCEPhysicsSetFixedDeltaTime(MCE_CTX, float value);

int32_t MCEPhysicsGetMaxSubsteps(MCE_CTX);
void MCEPhysicsSetMaxSubsteps(MCE_CTX, int32_t value);

float MCEPhysicsGetDefaultFriction(MCE_CTX);
void MCEPhysicsSetDefaultFriction(MCE_CTX, float value);

float MCEPhysicsGetDefaultRestitution(MCE_CTX);
void MCEPhysicsSetDefaultRestitution(MCE_CTX, float value);

float MCEPhysicsGetDefaultAngularDamping(MCE_CTX);
void MCEPhysicsSetDefaultAngularDamping(MCE_CTX, float value);

float MCEPhysicsGetDefaultLinearDamping(MCE_CTX);
void MCEPhysicsSetDefaultLinearDamping(MCE_CTX, float value);

uint32_t MCEPhysicsGetMaxBodies(MCE_CTX);
void MCEPhysicsSetMaxBodies(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetMaxBodyPairs(MCE_CTX);
void MCEPhysicsSetMaxBodyPairs(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetMaxContactConstraints(MCE_CTX);
void MCEPhysicsSetMaxContactConstraints(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetCCDEnabled(MCE_CTX);
void MCEPhysicsSetCCDEnabled(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetResolveInitialOverlap(MCE_CTX);
void MCEPhysicsSetResolveInitialOverlap(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetDeterministic(MCE_CTX);
void MCEPhysicsSetDeterministic(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetDebugDrawEnabled(MCE_CTX);
void MCEPhysicsSetDebugDrawEnabled(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetDebugDrawInPlay(MCE_CTX);
void MCEPhysicsSetDebugDrawInPlay(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetShowColliders(MCE_CTX);
void MCEPhysicsSetShowColliders(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetShowCOMAxes(MCE_CTX);
void MCEPhysicsSetShowCOMAxes(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetShowContacts(MCE_CTX);
void MCEPhysicsSetShowContacts(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetShowSleeping(MCE_CTX);
void MCEPhysicsSetShowSleeping(MCE_CTX, uint32_t value);

uint32_t MCEPhysicsGetShowOverlaps(MCE_CTX);
void MCEPhysicsSetShowOverlaps(MCE_CTX, uint32_t value);

#ifdef __cplusplus
} // extern "C"
#endif
