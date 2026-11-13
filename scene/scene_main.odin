package ravn_scene

import "core:log"
import "core:debug/trace"
import "core:os"
import "core:fmt"
import "core:flags"

// Dump util
// Run as 'odin run ravn\scene -- data\scene.rscn'
main :: proc() {
    context.assertion_failure_proc = trace.assertion_failure_proc
    context.logger = log.create_console_logger()

    Args :: struct {
        path:   string `args:"pos=0,required" usage:"Path to a .rscn file"`,
        data:   bool `usage:"Print large data (vertices, animations)"`,
        stats:  bool `usage:"Show size statistics"`,
    }

    args: Args
    flags.parse_or_exit(&args, os.args)

    scene, err := load(args.path)
    if err != nil {
        log.error("Failed to load:", err)
        os.exit(1)
    }

    fmt.printf("Scene %q = ", args.path)
    fmt.println(to_string(scene, include_data = args.data))

    if !validate(scene) {
        log.error("Validation failed.")
    }

    if args.stats {
        fmt.println("version                     =", scene.header.version)
        fmt.println("len(data)                   =", len(scene.data))
        fmt.println("len(string_data)            =", len(scene.string_data))
        fmt.println("len(node_data)              =", len(scene.node_data))
        fmt.println("len(image_data)             =", len(scene.image_data))
        fmt.println("len(mesh_data)              =", len(scene.mesh_data))
        fmt.println("len(skin_data)              =", len(scene.skin_data))
        fmt.println("len(spline_data)            =", len(scene.spline_data))
        fmt.println("len(skeleton_data)          =", len(scene.skeleton_data))
        fmt.println("len(bone_data)              =", len(scene.bone_data))
        fmt.println("len(anim_data)              =", len(scene.anim_data))
        fmt.println("len(mesh_vert_data)         =", len(scene.mesh_vert_data))
        fmt.println("len(skin_vert_data)         =", len(scene.skin_vert_data))
        fmt.println("len(spline_vert_data)       =", len(scene.spline_vert_data))
        fmt.println("len(index_data)             =", len(scene.index_data))
        fmt.println("len(anim_curve_data)        =", len(scene.anim_curve_data))
        fmt.println("len(anim_float3_frame_data) =", len(scene.anim_float3_frame_data))
        fmt.println("len(anim_float4_frame_data) =", len(scene.anim_float4_frame_data))
    }
}