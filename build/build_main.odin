#+vet unused style shadowing
package raven_build

import "../platform"
import "../base"
import "../base/ufmt"

import "core:strings"

ODIN_EXE :: "odin"

Command :: enum {
    Export_Web,
    Run_Hot,
    Build_Hot,
    Builtin_Shaders,
    Clean,
}

_command_name := [Command]string {
    .Export_Web = "export-web",
    .Run_Hot = "run-hot",
    .Build_Hot = "build-hot",
    .Clean = "clean",
    .Builtin_Shaders = "builtin-shaders",
}

_command_info := [Command]string {
    .Export_Web = "Compile the packge to WASM and package a web build",
    .Run_Hot = "Run the package in hot reload mode",
    .Build_Hot = "Only compile the hot reload DLL",
    .Clean = "Remove common temporary files",
    .Builtin_Shaders = "Precompile builtin shaders",
}

Flags :: struct {
    cmd:    Command `args:"pos=0,required" usage:"Only build, don't run"`,
    pkg:    string `args:"pos=1,required" usage:"The Odin package name to run/build"`,
}

parse_flags :: proc(params: []string) -> (flags: Flags, ok: bool) {
    show_help := false

    defer if show_help {
        ufmt.eprintfln("Raven build tool")
        ufmt.eprintfln("Usage:")
        ufmt.eprintfln("\tbuild command [arguments]")
        ufmt.eprintfln("Commands:")
        for cmd in Command {
            ufmt.eprintf("\t%v", _command_name[cmd])
            for _ in len(_command_name[cmd])..<30 {
                ufmt.eprintf(" ")
            }
            ufmt.eprintfln("%v", _command_info[cmd])
        }
        ufmt.eprintfln("")
    }

    if len(params) == 0 {
        show_help = true
        return {}, false
    }

    cmd_ok: bool
    for name, cmd in _command_name {
        if params[0] == name {
            flags.cmd = cmd
            cmd_ok = true
            break
        }
    }
    if !cmd_ok {
        base.log_err("Invalid command '%s'", params[0])
        show_help = true
        return {}, false
    }

    #partial switch flags.cmd {
    case .Builtin_Shaders, .Clean:

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
    case .Export_Web:
        if !export_web(strings.concatenate({pkg_name, "-web-export"}), pkg_name, fl.pkg) {
            base.log_err("Web export failed")
            platform.exit_process(1)
        }

    case .Run_Hot:
        clean_hot(pkg_name)
        compile_hot(fl.pkg, pkg_name = pkg_name, index = 0)
        hotreload_run(pkg_name, fl.pkg)
        clean_hot(pkg_name)

    case .Clean:
        remove_all("*.exe")
        remove_all("*.pdb")
        remove_all("*.rdi")

    case .Builtin_Shaders:
        if !compile_builtin_shaders() {
            base.log_err("Failed to compile builtin shaders")
            platform.exit_process(1)
        }

    case .Build_Hot:
        latest, _ := hotreload_find_latest_dll(pkg_name)
        base.log_info("Building %i", latest.index + 1)
        compile_hot(fl.pkg, pkg_name = pkg_name, index = latest.index + 1)
    }
}
