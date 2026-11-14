// Ravn Scene parser
#+vet explicit-allocators shadowing unused
package ravn_scene

import "core:log"
import "core:slice"
import "core:os"
import "base:intrinsics"

MAGIC :: (u32('r') << 0) | (u32('s') << 8) | (u32('c') << 16) | (u32('n') << 24)

// Incremented every time a non-backward-compatible change occurs. Assets need to be re-exported.
VERSION :: 2

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
    anim_frame_data:        []Anim_Frame,
}

String_Range :: distinct Range(u32)

Range :: struct($Int: typeid) where intrinsics.type_is_integer(Int) {
    offset: Int,
    length: Int,
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
    magic:              u32,
    version:            u32,
    string_range:       Range(u64),
    node_range:         Range(u64),
    image_range:        Range(u64),
    mesh_range:         Range(u64),
    skin_range:         Range(u64),
    spline_range:       Range(u64),
    skeleton_range:     Range(u64),
    bone_range:         Range(u64),
    anim_range:         Range(u64),
    mesh_vert_range:    Range(u64),
    skin_vert_range:    Range(u64),
    spline_vert_range:  Range(u64),
    index_range:        Range(u64),
    anim_curve_range:   Range(u64),
    anim_frame_range:   Range(u64),
}

Image :: struct #packed {
    path_range:     String_Range,
    mat_name_range: String_Range,
}

Node :: struct #packed {
    name_range:     String_Range,
    parent:     	u32,
    mat_name_range: String_Range,
    kind:       	Node_Kind,
    pos:        	[3]f32,
    rot:        	quaternion128,
    scale:      	[3]f32,
}

Mesh :: struct #packed {
    name_range:     String_Range,
    vert_range:     Range(u32),
    index_range:    Range(u32),
}

Skin :: struct #packed {
    name_range:     String_Range,
    skeleton:       u32,
    vert_range:     Range(u32),
    index_range:    Range(u32),
}

Skeleton :: struct #packed {
    name_range: String_Range,
    bone_range: Range(u32),
}

Bone :: struct #packed {
    skeleton:   u32,
    name_range: String_Range,
    parent:     u32,
    pos:        [3]f32,
    length:     f32,
    rot:        quaternion128,
}

Mesh_Vert :: struct #packed {
    pos:    [3]f32,
    uv:     [2]f32,
    nor:    [3]i8,
    col:    [3]u8,
}

Skin_Vert :: struct #packed {
    pos:        [3]f32,
    uv:         [2]f32,
    nor:        [3]i8,
    col:        [3]u8,
    bones:      [4]u8,
    weights:    [4]u8,
}

Anim :: struct #packed {
    skeleton:       u32,
    name_range:     String_Range,
    curve_range:    Range(u32),
}

Anim_Curve :: struct #packed {
    bone:           u32,
    pos_range:      Range(u32),
    rot_range:      Range(u32),
    scale_range:    Range(u32),
}

Anim_Frame :: struct #packed {
    time:  f32,
    value: [4]f32,
}

Spline :: struct #packed {
    name_range: String_Range,
    vert_range: Range(u32),
}

Spline_Vert :: struct #packed {
    pos:    [3]f32,
    rad:    f32,
    tilt:   f32,
}

load :: proc {
    load_from_path,
    load_from_data,
}

load_from_path :: proc(path: string, allocator := context.allocator) -> (result: Scene, err: Error) {
    data := os.read_entire_file(path, allocator = allocator) or_return
    return load_from_data(data)
}

load_from_data :: proc(data: []byte) -> (result: Scene, err: Error) {
    if len(data) < size_of(Header) {
        return {}, .Invalid_Size
    }

    header := cast(^Header)raw_data(data)

    if header.magic != MAGIC {
        log.error("Invalid magic")
        return {}, .Invalid_Magic
    }

    if header.version != VERSION {
        log.error("Invalid version")
        return {}, .Invalid_Version
    }

    result.string_data           = slice.reinterpret([]byte,        get_range_slice(data, header.string_range))
    result.node_data             = slice.reinterpret([]Node,        get_range_slice(data, header.node_range))
    result.image_data            = slice.reinterpret([]Image,       get_range_slice(data, header.image_range))
    result.mesh_data             = slice.reinterpret([]Mesh,        get_range_slice(data, header.mesh_range))
    result.skin_data             = slice.reinterpret([]Skin,        get_range_slice(data, header.skin_range))
    result.spline_data           = slice.reinterpret([]Spline,      get_range_slice(data, header.spline_range))
    result.skeleton_data         = slice.reinterpret([]Skeleton,    get_range_slice(data, header.skeleton_range))
    result.bone_data             = slice.reinterpret([]Bone,        get_range_slice(data, header.bone_range))
    result.anim_data             = slice.reinterpret([]Anim,        get_range_slice(data, header.anim_range))
    result.mesh_vert_data        = slice.reinterpret([]Mesh_Vert,   get_range_slice(data, header.mesh_vert_range))
    result.skin_vert_data        = slice.reinterpret([]Skin_Vert,   get_range_slice(data, header.skin_vert_range))
    result.spline_vert_data      = slice.reinterpret([]Spline_Vert, get_range_slice(data, header.spline_vert_range))
    result.index_data            = slice.reinterpret([]u32,         get_range_slice(data, header.index_range))
    result.anim_curve_data       = slice.reinterpret([]Anim_Curve,  get_range_slice(data, header.anim_curve_range))
    result.anim_frame_data       = slice.reinterpret([]Anim_Frame,  get_range_slice(data, header.anim_frame_range))

    result.header = header^
    result.data = data

    return result, nil
}

// Range is offset + len
range_is_valid :: proc(data: []$T, range: $R/Range($I)) -> bool {
    offset := u64(range.offset)
    length := u64(range.length)
    data_len := u64(len(data))
    return offset <= data_len && length <= data_len - offset
}

is_in_range :: proc(range: $R/Range($I), index: I) -> bool {
    return index >= range.offset && index < range.offset + range.length
}

// Range is offset + len
get_range_slice :: proc(data: []$T, range: $R/Range($I)) -> []T {
    if !range_is_valid(data, range) {
        return nil
    }
    return data[range.offset:][:range.length]
}

get_string          :: proc(scn: Scene, range: String_Range) -> string        { return string(get_range_slice(scn.string_data, range)) }
get_bones           :: proc(scn: Scene, range: Range(u32)) -> []Bone          { return get_range_slice(scn.bone_data, range) }
get_anims           :: proc(scn: Scene, range: Range(u32)) -> []Anim          { return get_range_slice(scn.anim_data, range) }
get_mesh_verts      :: proc(scn: Scene, range: Range(u32)) -> []Mesh_Vert     { return get_range_slice(scn.mesh_vert_data, range) }
get_skin_verts      :: proc(scn: Scene, range: Range(u32)) -> []Skin_Vert     { return get_range_slice(scn.skin_vert_data, range) }
get_spline_verts    :: proc(scn: Scene, range: Range(u32)) -> []Spline_Vert   { return get_range_slice(scn.spline_vert_data, range) }
get_indices         :: proc(scn: Scene, range: Range(u32)) -> []u32           { return get_range_slice(scn.index_data, range) }
get_anim_curves     :: proc(scn: Scene, range: Range(u32)) -> []Anim_Curve    { return get_range_slice(scn.anim_curve_data, range) }
get_anim_frames     :: proc(scn: Scene, range: Range(u32)) -> []Anim_Frame    { return get_range_slice(scn.anim_frame_data, range) }
