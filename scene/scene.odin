// Ravn Scene parser
#+vet explicit-allocators shadowing unused
package ravn_scene

import "core:slice"
import "core:os"
import "base:intrinsics"

MAGIC :: (u32('r') << 0) | (u32('s') << 8) | (u32('c') << 16) | (u32('n') << 24)
VERSION :: 0

INVALID_PARENT :: 0xffff_ffff

Scene :: struct {
    header:	Header,
    data:	[]byte,

    string_data:            []byte,
    node_data:              []Node,
    image_data:             []Image,
    mesh_data:              []Mesh,
    skin_data:              []Skin,
    spline_data:            []Spline,
    skeleton_data:          []Skeleton,
    bone_data:              []Bone,
    anim_data:              []Anim,
    mesh_vert_data:         []Mesh_Vert,
    skin_vert_data:         []Skin_Vert,
    spline_vert_data:       []Spline_Vert,
    index_data:             []u32,
    anim_curve_data:        []Anim_Curve,
    anim_float3_frame_data: [][3]f32,
    anim_float4_frame_data: [][4]f32,
}

Error :: union #shared_nil {
    Load_Error,
    os.Error,
}

Load_Error :: enum u32 {
    None = 0,

    Invalid_Size,
    Invalid_Magic,
    Invalid_Version,
}

Node_Kind :: enum u8 {
    None = 0,
    Mesh = 1,
    Skin = 2,
    Spline = 3,
}

Header :: struct #packed {
    magic:                   u32,
    version:                 u32,
    string_range:            [2]u64,
    node_range:              [2]u64,
    image_range:             [2]u64,
    mesh_range:              [2]u64,
    skin_range:              [2]u64,
    spline_range:            [2]u64,
    skeleton_range:          [2]u64,
    bone_range:              [2]u64,
    anim_range:              [2]u64,
    mesh_vert_range:         [2]u64,
    skin_vert_range:         [2]u64,
    spline_vert_range:       [2]u64,
    index_range:             [2]u64,
    anim_curve_range:        [2]u64,
    anim_float3_frame_range: [2]u64,
    anim_float4_frame_range: [2]u64,
}

Image :: struct #packed {
    path_range:     [2]u32,
    mat_name_range: [2]u32,
}

Node :: struct #packed {
    name_range: 			[2]u32,
    parent:     			u32,
    material_name_range:	[2]u32,
    kind:       			Node_Kind,
    pos:        			[3]f32,
    rot:        			quaternion128,
    scale:      			[3]f32,
}

Mesh :: struct #packed {
    name_range:  [2]u32,
    vert_range:  [2]u32,
    index_range: [2]u32,
}

Skin :: struct #packed {
    name_range:  [2]u32,
    skeleton:    u32,
    vert_range:  [2]u32,
    index_range: [2]u32,
}

Skeleton :: struct #packed {
    name_range: [2]u32,
    bone_range: [2]u32,
}

Bone :: struct #packed {
    name_range: [2]u32,
    parent:     u32,
    pos:        [3]f32,
    length:     f32,
    rot:        quaternion128,
}

Anim :: struct #packed {
    name_range:  [2]u32,
    curve_range: [2]u32,
}

Mesh_Vert :: struct #packed {
    pos: [3]f32,
    uv:  [2]f32,
    nor: [3]i8,
    col: [3]u8,
}

Skin_Vert :: struct #packed {
    pos:     [3]f32,
    uv:      [2]f32,
    nor:     [3]i8,
    col:     [3]u8,
    bones:   [4]u8,
    weights: [4]u8,
}

Spline :: struct #packed {
    name_range: [2]u32,
    vert_range: [2]u32,
}

Spline_Vert :: struct #packed {
    pos:  [3]f32,
    rad:  f32,
    tilt: f32,
}

Anim_Curve :: struct #packed {
    name_range:  [2]u32,
    pos_range:   [2]u32,
    rot_range:   [2]u32,
    scale_range: [2]u32,
}

Anim_Float3_Frame :: struct #packed {
    time:  u32,
    value: [3]f32,
}

Anim_Float4_Frame :: struct #packed {
    time:  u32,
    value: [4]f32,
}

load :: proc {
    load_from_path,
    load_from_data,
}

load_from_path :: proc(path: string, allocator := context.allocator) -> (scene: Scene, err: Error) {
    data := os.read_entire_file(path, allocator = allocator) or_return
    return load_from_data(data)
}

load_from_data :: proc(data: []byte) -> (scene: Scene, err: Error) {
    if len(data) < size_of(Header) {
        return {}, .Invalid_Size
    }

    header := cast(^Header)raw_data(data)

    if header.magic != MAGIC {
        return {}, .Invalid_Magic
    }

    if header.version != VERSION {
        return {}, .Invalid_Version
    }

    scene.string_data            = slice.reinterpret([]byte,        get_range_slice(data, header.string_range))
    scene.node_data              = slice.reinterpret([]Node,        get_range_slice(data, header.node_range))
    scene.image_data             = slice.reinterpret([]Image,       get_range_slice(data, header.image_range))
    scene.mesh_data              = slice.reinterpret([]Mesh,        get_range_slice(data, header.mesh_range))
    scene.skin_data              = slice.reinterpret([]Skin,        get_range_slice(data, header.skin_range))
    scene.spline_data            = slice.reinterpret([]Spline,      get_range_slice(data, header.spline_range))
    scene.skeleton_data          = slice.reinterpret([]Skeleton,    get_range_slice(data, header.skeleton_range))
    scene.bone_data              = slice.reinterpret([]Bone,        get_range_slice(data, header.bone_range))
    scene.anim_data              = slice.reinterpret([]Anim,        get_range_slice(data, header.anim_range))
    scene.mesh_vert_data         = slice.reinterpret([]Mesh_Vert,   get_range_slice(data, header.mesh_vert_range))
    scene.skin_vert_data         = slice.reinterpret([]Skin_Vert,   get_range_slice(data, header.skin_vert_range))
    scene.spline_vert_data       = slice.reinterpret([]Spline_Vert, get_range_slice(data, header.spline_vert_range))
    scene.index_data             = slice.reinterpret([]u32,         get_range_slice(data, header.index_range))
    scene.anim_curve_data        = slice.reinterpret([]Anim_Curve,  get_range_slice(data, header.anim_curve_range))
    scene.anim_float3_frame_data = slice.reinterpret([][3]f32,      get_range_slice(data, header.anim_float3_frame_range))
    scene.anim_float4_frame_data = slice.reinterpret([][4]f32,      get_range_slice(data, header.anim_float4_frame_range))

    scene.header = header^
    scene.data = data

    return scene, nil
}

// Range is offset + len
get_range_slice :: proc(data: []$T, range: [2]$Int) -> []T where intrinsics.type_is_integer(Int) {
    return data[range[0]:][:range[1]]
}
