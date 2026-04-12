#ifndef RAVEN
#define RAVEN 1

#define RV_CONSTANTS_BIND_SLOTS 8
#define RV_SAMPLER_BIND_SLOTS 8
#define RV_RESOURCE_BIND_SLOTS 32
#define RV_RW_RESOURCE_BIND_SLOTS 32

#define RV_SAMPLER_SLOT_SHIFT 0
#define RV_CONSTANTS_SLOT_SHIFT (RV_SAMPLER_SLOT_SHIFT + RV_SAMPLER_BIND_SLOTS)
#define RV_RESOURCE_SLOT_SHIFT (RV_CONSTANTS_SLOT_SHIFT + RV_CONSTANTS_BIND_SLOTS)
#define RV_RW_RESOURCE_SLOT_SHIFT (RV_RESOURCE_SLOT_SHIFT + RV_RESOURCE_BIND_SLOTS)

#define _RV_JOIN(a, b) a ## b

#ifdef __SLANG__
#define RV_SAMPLER_SLOT(slot, decl) [[vk::binding(slot + RV_SAMPLER_SLOT_SHIFT, 0)]] decl
#define RV_CONSTANTS_SLOT(slot, decl) [[vk::binding(slot + RV_CONSTANTS_SLOT_SHIFT, 0)]] decl
#define RV_RESOURCE_SLOT(slot, decl) [[vk::binding(slot + RV_RESOURCE_SLOT_SHIFT, 0)]] decl
#define RV_RW_RESOURCE_SLOT(slot, decl) [[vk::binding(slot + RV_RW_RESOURCE_SLOT_SHIFT, 0)]] decl
#else
#define RV_SAMPLER_SLOT(slot, decl) decl : register(_RV_JOIN(s, slot))
#define RV_CONSTANTS_SLOT(slot, decl) decl : register(_RV_JOIN(b, slot))
#define RV_RESOURCE_SLOT(slot, decl) decl : register(_RV_JOIN(t, slot))
#define RV_RW_RESOURCE_SLOT(slot, decl) decl : register(_RV_JOIN(u, slot))
#endif


float4 rv_unpack_unorm8(uint val) {
    return float4(
        (val      ) & 0xff,
        (val >>  8) & 0xff,
        (val >> 16) & 0xff,
        (val >> 24) & 0xff
    ) * (1.0f / 255.0f);
}

float2 rv_unpack_unorm16(uint val) {
    return float2(
        (val      ) & 0xffff,
        (val >> 16) & 0xffff
    ) * (1.0f / 65535.0f);
}


float4 rv_unpack_signed_color_unorm8(uint val) {
    return rv_unpack_unorm8(val) * 4.0f - 2.0f;
}

float2 rv_unpack_uv_unorm16(uint val) {
    return rv_unpack_unorm16(val) * 16.0f - 8.0f;
}


// Data

RV_CONSTANTS_SLOT(0, cbuffer rv_global_constants) {
    float rv_global_time;
    float rv_global_delta_time;
    uint  rv_global_frame;
    int2  rv_global_resolution;
    uint  rv_global_rand_seed;
    uint4 rv_global_param;
}

RV_CONSTANTS_SLOT(1, cbuffer rv_layer_constants) {
    float4x4 rv_view_proj;
    float3 rv_cam_pos;
    int rv_layer_index;
}

RV_CONSTANTS_SLOT(2, cbuffer rv_batch_constants) {
    uint rv_instance_offset;
    uint _pad0;
    uint _pad1;
    uint _pad2;
}


// Mesh Vertex

struct RV_Vertex_Packed {
    float4  pos;
    float2  uv;
    uint    normal;
    uint    col;
};

struct RV_Vertex {
    float3 pos;
    float2 uv;
    float3 normal;
    float4 col;
};

RV_Vertex rv_unpack_vertex(RV_Vertex_Packed packed) {
    RV_Vertex res;
    res.pos = packed.pos.xyz;
    res.uv = packed.uv;
    res.normal = rv_unpack_unorm8(packed.normal).xyz;
    res.col = rv_unpack_unorm8(packed.col);
    return res;
}


// Sprite Instance

struct RV_Sprite_Inst_Packed {
    float4 pos_col;
    float4 mat_x_uv_min;
    float4 mat_y_uv_size;
    uint   add_col;
    uint   param;
    uint   tex_slice;
    uint   _pad0;
};

struct RV_Sprite_Inst {
    float3 pos;
    float4 col;
    float3 mat_x;
    float3 mat_y;
    float2 uv_min;
    float2 uv_size;
    float4 add_col;
    uint param;
    uint tex_slice;
};

RV_Sprite_Inst rv_unpack_sprite_inst(RV_Sprite_Inst_Packed packed) {
    RV_Sprite_Inst res;
    res.pos = packed.pos_col.xyz;
    res.col = rv_unpack_signed_color_unorm8(asuint(packed.pos_col.w));
    res.mat_x = packed.mat_x_uv_min.xyz;
    res.mat_y = packed.mat_y_uv_size.xyz;
    res.uv_min = rv_unpack_uv_unorm16(asuint(packed.mat_x_uv_min.w));
    res.uv_size = rv_unpack_uv_unorm16(asuint(packed.mat_y_uv_size.w));
    res.add_col = rv_unpack_signed_color_unorm8(packed.add_col);
    res.param = packed.param;
    res.tex_slice = packed.tex_slice;
    return res;
}


// Mesh Instance

struct RV_Mesh_Inst_Packed {
    float4 pos_col;
    float4 mat_x_add_col;
    float4 mat_y_tex_slice_vert_offs;
    float4 mat_z_param;
};

struct RV_Mesh_Inst {
    float3 pos;
    float4 col;
    float3x3 mat;
    float4 add_col;
    uint tex_slice;
    uint vert_offs;
    uint param;
};

RV_Mesh_Inst rv_unpack_mesh_inst(RV_Mesh_Inst_Packed packed) {
    RV_Mesh_Inst res;
    res.pos = packed.pos_col.xyz;
    res.col = rv_unpack_signed_color_unorm8(asuint(packed.pos_col.w));
    res.mat = float3x3(
        packed.mat_x_add_col.xyz,
        packed.mat_y_tex_slice_vert_offs.xyz,
        packed.mat_z_param.xyz);
    res.add_col = rv_unpack_signed_color_unorm8(asuint(packed.mat_x_add_col.w));
    res.tex_slice = (asuint(packed.mat_y_tex_slice_vert_offs.w) >> 0) & 0xff;
    res.vert_offs = (asuint(packed.mat_y_tex_slice_vert_offs.w) >> 8) & 0xff;
    res.param = asuint(packed.mat_z_param.w);
    return res;
}


// Vertex -> Pixel data
struct RV_Varyings {
    float4 pos : SV_Position;
    float3 world_pos : POS;
    float3 normal : NOR;
    float2 uv : TEX;
    float4 col : COL;
    float4 add_col : ADD_COL;
    nointerpolation uint tex_slice : TEXSLICE;
};

// Calculate luminance (Y) from color.
// Uses CIE 1931 assuming Rec709 RGB values.
float luminance(float3 rgb) {
    return dot(rgb, float3(0.2126f, 0.7152f, 0.0722f));
}

// Calculates schlick fresnel term.
// f0: The fresnel reflectance an grazing angle.
// angle: The angle between view and half-vector.
float3 fresnel(float3 f0, float angle) {
    return f0 + (1.0 - f0) * pow(1.0 - angle, 5.0);
}

float3x3 adjugate(float3x3 m) {
    return float3x3(
        cross(m[1], m[2]),
        cross(m[2], m[0]),
        cross(m[0], m[1]));
}

#endif // RAVEN