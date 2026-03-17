#+vet unused style shadowing
package raven_build

import "../platform"
import "../base"

import "core:strings"
import "core:reflect"

ODIN_EXE :: "odin"

Command :: enum {
    export,
    export_web,
    run_hot,
    build_hot,
    compile_builtin_shaders,
}

Flags :: struct {
    cmd:    Command `args:"pos=0,required" usage:"Only build, don't run"`,
    pkg:    string `args:"pos=1,required" usage:"The Odin package name to run/build"`,
}

parse_flags :: proc(params: []string) -> (flags: Flags, ok: bool) {
    show_help := true

    if len(params) == 0 {
        show_help = true
        return {}, false
    }

    cmd_ok: bool
    flags.cmd, cmd_ok = reflect.enum_from_name(Command, params[0])
    if !cmd_ok {
        base.log_err("Invalid command '%s'. Must be one of:", params[0])
        for cmd in Command {
            base.log_err("\t%v", cmd)
        }
        return {}, false
    }

    #partial switch flags.cmd {
    case .compile_builtin_shaders:

    case:
        if len(params) < 2 {
            base.log_err("Package path missing")
            return {}, false
        }

        flags.pkg = params[1]
    }

    return flags, true
}

main :: proc() {
    context.logger = base.make_logger()

    args := platform.get_commandline_args(context.allocator)

    fl, fl_ok := parse_flags(args[1:])
    if !fl_ok {
        base.log_err("Invalid arguments")
        platform.exit_process(1)
    }

    pkg_name := fl.pkg[find_last_slash(fl.pkg)+1:]

    init()

    switch fl.cmd {
    case .export:
        unimplemented()

    case .export_web:
        if !export_web(strings.concatenate({pkg_name, "-web-export"}), pkg_name, fl.pkg) {
            base.log_err("Web export failed")
            platform.exit_process(1)
        }

    case .run_hot:
        clean_hot(pkg_name)
        compile_hot(fl.pkg, pkg_name = pkg_name, index = 0)
        hotreload_run(pkg_name, fl.pkg)
        clean_hot(pkg_name)

    case .compile_builtin_shaders:
        if !compile_builtin_shaders() {
            base.log_err("Failed to compile builtin shaders")
            platform.exit_process(1)
        }

    case .build_hot:
        latest, _ := hotreload_find_latest_dll(pkg_name)
        base.log_info("Building %i", latest.index + 1)
        compile_hot(fl.pkg, pkg_name = pkg_name, index = latest.index + 1)
    }
}
