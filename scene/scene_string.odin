package ravn_scene

import "core:strings"
import "core:fmt"

to_string :: proc(scene: Scene, include_data := false, allocator := context.allocator) -> string {
    sb: strings.Builder
    _, sb_err := strings.builder_init_len_cap(&sb, 0, 4096, allocator = allocator)
    if sb_err != nil {
        return fmt.aprintfln("String Builder Error: %v", sb_err)
    }
    fmt.sbprintln(&sb, "{")

    // Images
    if len(scene.image_data) > 0 {
        fmt.sbprintln(&sb, "\timages = {")
        for it in scene.image_data {
            fmt.sbprintfln(&sb, "\t\t%q = {{ material=%q }},",
                get_range_slice(scene.string_data, it.path_range),
                get_range_slice(scene.string_data, it.mat_name_range),
            )
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Nodes
    if len(scene.node_data) > 0 {
        fmt.sbprintln(&sb, "\tnodes = {")
        for it in scene.node_data {
            fmt.sbprintfln(&sb, "\t\t%q = {{ parent=%q, material=%q, kind=%v, pos=%v, rot=%v, scale=%v }},",
                get_range_slice(scene.string_data, it.name_range),
                (it.parent == INVALID_PARENT) ? "<NONE>" : string(get_range_slice(scene.string_data, scene.node_data[it.parent].name_range)),
                get_range_slice(scene.string_data, it.material_name_range),
                it.kind,
                it.pos,
                transmute([4]f32)it.rot,
                it.scale,
            )
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Meshes
    if len(scene.mesh_data) > 0 {
        fmt.sbprintln(&sb, "\tmeshes = {")
        for it in scene.mesh_data {
            fmt.sbprintf(&sb, "\t\t%q = {{",
                get_range_slice(scene.string_data, it.name_range),
            )
            verts := get_range_slice(scene.mesh_vert_data, it.vert_range)
            indices := get_range_slice(scene.index_data, it.index_range)
            format_vert_data(&sb, include_data, verts, indices)
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Skins
    if len(scene.skin_data) > 0 {
        fmt.sbprintln(&sb, "\tskins = {")
        for it in scene.skin_data {
            skel := scene.skeleton_data[it.skeleton]
            fmt.sbprintf(&sb, "\t\t%q = {{ skeleton=%q,",
                get_range_slice(scene.string_data, it.name_range),
                get_range_slice(scene.string_data, skel.name_range),
            )
            verts := get_range_slice(scene.skin_vert_data, it.vert_range)
            indices := get_range_slice(scene.index_data, it.index_range)
            format_vert_data(&sb, include_data, verts, indices)
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Splines
    if len(scene.spline_data) > 0 {
        fmt.sbprintln(&sb, "\tsplines = {")
        for it in scene.spline_data {
            fmt.sbprintf(&sb, "\t\t%q = {{", get_range_slice(scene.string_data, it.name_range))
            verts := get_range_slice(scene.spline_vert_data, it.vert_range)
            if include_data {
                fmt.sbprintfln(&sb, "\n\t\t\tverts = {{")
                for v in verts {
                    fmt.sbprintfln(&sb, "\t\t\t\t%v,", v)
                }
                fmt.sbprintfln(&sb, "\t\t\t}},")
                fmt.sbprintfln(&sb, "\t\t}},")
            } else {
                fmt.sbprintf(&sb, " num_verts=%i ", len(verts))
                fmt.sbprintfln(&sb, "}},")
            }
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Skeletons
    if len(scene.skeleton_data) > 0 {
        fmt.sbprintln(&sb, "\tskeletons = {")
        for it in scene.skeleton_data {
            fmt.sbprintfln(&sb, "\t\t%q = {{", get_range_slice(scene.string_data, it.name_range))
            bones := get_range_slice(scene.bone_data, it.bone_range)
            for b in bones {
                fmt.sbprintfln(&sb, "\t\t\t%q = {{ parent=%q, pos=%v, length=%f, rot=%v }},",
                    get_range_slice(scene.string_data, b.name_range),
                    (b.parent == INVALID_PARENT) ? "<NONE>" : string(get_range_slice(scene.string_data, scene.bone_data[b.parent].name_range)),
                    b.pos,
                    b.length,
                    transmute([4]f32)b.rot,
                )
            }
            fmt.sbprintln(&sb, "\t\t},")
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Animations
    if len(scene.anim_data) > 0 {
        fmt.sbprintln(&sb, "\tanims = {")
        for it in scene.anim_data {
            fmt.sbprintfln(&sb, "\t\t%q = {{", get_range_slice(scene.string_data, it.name_range))
            curves := get_range_slice(scene.anim_curve_data, it.curve_range)
            for c in curves {
                if include_data {
                    fmt.sbprintfln(&sb, "\t\t\t%q = {{", get_range_slice(scene.string_data, c.name_range))
                    fmt.sbprintln(&sb, "\t\t\t\tpos_frames = {")
                    for frame in get_range_slice(scene.anim_float3_frame_data, c.pos_range) {
                        fmt.sbprintfln(&sb, "\t\t\t\t\ttime=%d, value=%v,", frame.time, frame.value)
                    }
                    fmt.sbprintln(&sb, "\t\t\t\t},")
                    fmt.sbprintln(&sb, "\t\t\t\trot_frames = {")
                    for frame in get_range_slice(scene.anim_float4_frame_data, c.rot_range) {
                        fmt.sbprintfln(&sb, "\t\t\t\t\ttime=%d, value=%v,", frame.time, frame.value)
                    }
                    fmt.sbprintln(&sb, "\t\t\t\t},")
                    fmt.sbprintln(&sb, "\t\t\t\tscale_frames = {")
                    for frame in get_range_slice(scene.anim_float3_frame_data, c.scale_range) {
                        fmt.sbprintfln(&sb, "\t\t\t\t\ttime=%d, value=%v,", frame.time, frame.value)
                    }
                    fmt.sbprintln(&sb, "\t\t\t\t},")
                    fmt.sbprintln(&sb, "\t\t\t},")
                } else {
                    fmt.sbprintfln(&sb, "\t\t\t%q = {{ num_pos=%d, num_rot=%d, num_scale=%d }},",
                        get_range_slice(scene.string_data, c.name_range),
                        c.pos_range[1],
                        c.rot_range[1],
                        c.scale_range[1],
                    )
                }
            }
            fmt.sbprintln(&sb, "\t\t},")
        }
        fmt.sbprintln(&sb, "\t},")
    }

    fmt.sbprintln(&sb, "}")
    return strings.to_string(sb)

    // Includes closing brace
    format_vert_data :: proc(sb: ^strings.Builder, include_data: bool, verts: []$V, indices: []u32) {
        if include_data {
            fmt.sbprintfln(sb, "\n\t\t\tverts = {{")
            for v in verts {
                fmt.sbprintfln(sb, "\t\t\t\t%v,", v)
            }
            fmt.sbprintfln(sb, "\t\t\t}},")
            fmt.sbprintfln(sb, "\t\t\tindices = {{")
            for i := 0; i < len(indices); i += 3 {
                fmt.sbprintfln(sb, "\t\t\t\t%v, %v, %v,", indices[i], indices[i+1], indices[i+2])
            }
            fmt.sbprintfln(sb, "\t\t\t}},")
            fmt.sbprintfln(sb, "\t\t}},")
        } else {
            fmt.sbprintf(sb, " num_verts=%i, num_tris=%i ", len(verts), len(indices) / 3)
            fmt.sbprintfln(sb, "}},")
        }
    }
}
