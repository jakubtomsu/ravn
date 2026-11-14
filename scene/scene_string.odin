package ravn_scene

import "core:strings"
import "core:fmt"

to_string :: proc(scn: Scene, include_data := false, allocator := context.allocator) -> string {
    sb: strings.Builder
    _, sb_err := strings.builder_init_len_cap(&sb, 0, 4096, allocator = allocator)
    if sb_err != nil {
        return fmt.aprintfln("String Builder Error: %v", sb_err)
    }
    fmt.sbprintln(&sb, "{")

    // Images
    if len(scn.image_data) > 0 {
        fmt.sbprintln(&sb, "\timages = {")
        for it, i in scn.image_data {
            fmt.sbprintfln(&sb, "\t\t[%i] %q = {{ material=%q }},",
                i,
                get_string(scn, it.path_range),
                get_string(scn, it.mat_name_range),
            )
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Nodes
    if len(scn.node_data) > 0 {
        fmt.sbprintln(&sb, "\tnodes = {")
        for it, i in scn.node_data {
            fmt.sbprintfln(&sb, "\t\t[%i] %q = {{ parent=%q, material=%q, kind=%v, pos=%v, rot=%v, scale=%v }},",
                i,
                get_string(scn, it.name_range),
                (it.parent == INVALID_PARENT) ? "<NONE>" : string(get_string(scn, scn.node_data[it.parent].name_range)),
                get_string(scn, it.mat_name_range),
                it.kind,
                it.pos,
                transmute([4]f32)it.rot,
                it.scale,
            )
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Meshes
    if len(scn.mesh_data) > 0 {
        fmt.sbprintln(&sb, "\tmeshes = {")
        for it, i in scn.mesh_data {
            fmt.sbprintf(&sb, "\t\t[%i] %q = {{",
                i,
                get_string(scn, it.name_range),
            )
            verts := get_mesh_verts(scn, it.vert_range)
            indices := get_indices(scn, it.index_range)
            format_vert_data(&sb, include_data, verts, indices)
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Skins
    if len(scn.skin_data) > 0 {
        fmt.sbprintln(&sb, "\tskins = {")
        for it, i in scn.skin_data {
            skel := scn.skeleton_data[it.skeleton]
            fmt.sbprintf(&sb, "\t\t[%i] %q = {{ skeleton=%q,",
                i,
                get_string(scn, it.name_range),
                get_string(scn, skel.name_range),
            )
            verts := get_skin_verts(scn, it.vert_range)
            indices := get_indices(scn, it.index_range)
            format_vert_data(&sb, include_data, verts, indices)
        }
        fmt.sbprintln(&sb, "\t},")
    }

    // Splines
    if len(scn.spline_data) > 0 {
        fmt.sbprintln(&sb, "\tsplines = {")
        for it, i in scn.spline_data {
            fmt.sbprintf(&sb, "\t\t[%i] %q = {{", i, get_string(scn, it.name_range))
            verts := get_spline_verts(scn, it.vert_range)
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
    if len(scn.skeleton_data) > 0 {
        fmt.sbprintln(&sb, "\tskeletons = {")
        for it, i in scn.skeleton_data {
            fmt.sbprintfln(&sb, "\t\t[%i] %q = {{", i, get_string(scn, it.name_range))
            bones := get_bones(scn, it.bone_range)
            for b, b_i in bones {
                fmt.sbprintfln(&sb, "\t\t\t[%i] %q = {{ parent=%q, pos=%v, length=%f, rot=%v }},",
                    b_i,
                    get_string(scn, b.name_range),
                    (b.parent == INVALID_PARENT) ? "<NONE>" : string(get_string(scn, scn.bone_data[b.parent].name_range)),
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
    if len(scn.anim_data) > 0 {
        fmt.sbprintln(&sb, "\tanims = {")
        for it, i in scn.anim_data {
            skel_name := it.skeleton != max(u32) ? string(get_string(scn, scn.skeleton_data[it.skeleton].name_range)) : "INVALID"
            fmt.sbprintfln(&sb, "\t\t[%i] %q = {{ skeleton = %q,", i, get_string(scn, it.name_range), skel_name)
            curves := get_anim_curves(scn, it.curve_range)
            for c in curves {
                name := get_string(scn, scn.bone_data[c.bone].name_range)
                if include_data {
                    fmt.sbprintfln(&sb, "\t\t\t%q = {{", name)
                    fmt.sbprintln(&sb, "\t\t\t\tpos_frames = {")
                    for frame in get_anim_frames(scn, c.pos_range) {
                        fmt.sbprintfln(&sb, "\t\t\t\t\ttime=%v, value=%v,", frame.time, frame.value.xyz)
                    }
                    fmt.sbprintln(&sb, "\t\t\t\t},")
                    fmt.sbprintln(&sb, "\t\t\t\trot_frames = {")
                    for frame in get_anim_frames(scn, c.rot_range) {
                        fmt.sbprintfln(&sb, "\t\t\t\t\ttime=%v, value=%v,", frame.time, frame.value)
                    }
                    fmt.sbprintln(&sb, "\t\t\t\t},")
                    fmt.sbprintln(&sb, "\t\t\t\tscale_frames = {")
                    for frame in get_anim_frames(scn, c.scale_range) {
                        fmt.sbprintfln(&sb, "\t\t\t\t\ttime=%v, value=%v,", frame.time, frame.value.xyz)
                    }
                    fmt.sbprintln(&sb, "\t\t\t\t},")
                    fmt.sbprintln(&sb, "\t\t\t},")
                } else {
                    fmt.sbprintfln(&sb, "\t\t\t%q = {{ num_pos=%d, num_rot=%d, num_scale=%d }},",
                        name,
                        c.pos_range.length,
                        c.rot_range.length,
                        c.scale_range.length,
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
