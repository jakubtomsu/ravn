#ifndef GPU_HLSLI_INCLUDED
#define GPU_HLSLI_INCLUDED

#include "gpu_shared_defs.hlsli"

#define _GPU_JOIN(a, b) a ## b

#ifdef __SLANG__
#define GPU_SAMPLER_SLOT(slot, group, decl) [[vk::binding(slot, group)]] decl
#define GPU_CONSTANTS_SLOT(slot, group, decl) [[vk::binding(slot, group)]] decl
#define GPU_RESOURCE_SLOT(slot, group, decl) [[vk::binding(slot, group)]] decl
#define GPU_RW_RESOURCE_SLOT(slot, group, decl) [[vk::binding(slot, group)]] decl
#else
#define GPU_SAMPLER_SLOT(slot, group, decl) decl : register(_GPU_JOIN(s, slot + GPU_MAX_BIND_GROUP_SAMPLERS * group))
#define GPU_CONSTANTS_SLOT(slot, group, decl) decl : register(_GPU_JOIN(b, slot + GPU_MAX_BIND_GROUP_CONSTANTS * group))
#define GPU_RESOURCE_SLOT(slot, group, decl) decl : register(_GPU_JOIN(t, slot + GPU_MAX_BIND_GROUP_RESOURCES * group))
#define GPU_RW_RESOURCE_SLOT(slot, group, decl) decl : register(_GPU_JOIN(u, slot + GPU_MAX_BIND_GROUP_RW_RESOURCES * group))
#endif

#endif