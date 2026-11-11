#+vet shadowing style unused
package ravn_shaderc

import "core:strings"
import "core:log"
import "core:debug/trace"
import "core:os"
import "core:flags"

// Commandline shader compilation util
main :: proc() {
    context.assertion_failure_proc = trace.assertion_failure_proc
    context.logger = log.create_console_logger()

    Args :: struct {
        path:       string `args:"pos=0,required" usage:"File or directory path"`,
        targets:    bit_set[Target] `usage:"Output format targets, default is DXBC and WGSL"`,
        stage:      Stage `usage:"Optional shader stage"`,
        release:    bool `usage:"Build in optimized release mode"`,
    }

    args := Args{}
    args.targets = {.DXBC, .WGSL}
    flags.parse_or_exit(&args, os.args)

    if .Invalid in args.targets {
        log.error("Got invalid target")
        os.exit(1)
    }

    if args.targets == {} {
        log.error("No targets provided")
        os.exit(1)
    }

    if !init() {
        log.error("Failed to init shader compiler")
        os.exit(1)
    }
    defer shutdown()

    opts := DEFAULT_OPTIONS
    opts.release = args.release
    opts.stage = args.stage

    if os.is_file(args.path) {
        _compile_targets(args.path, opts, args.targets)

    } else if os.is_dir(args.path) {
        append(&opts.include_dirs, args.path)

        files, err := os.read_directory_by_path(args.path, 4096, context.temp_allocator)
        if err != nil {
            log.error("Failed to read directory:", err)
            os.exit(1)
        }

        any_file := false
        for fi in files {
            if
                strings.ends_with(fi.name, ".vs.slang") ||
                strings.ends_with(fi.name, ".ps.slang") ||
                strings.ends_with(fi.name, ".cs.slang")
            {
                _compile_targets(fi.fullpath, opts, args.targets)
                any_file = true
            }
        }

        if !any_file {
            log.warnf("No shader files found in %q, ensure you use correct file suffixes", args.path)
            os.exit(1)
        }

    } else {
        log.error("Path must be file or a directory")
    }

    log.info("Compilation finished successfully.")

    return

    _compile_targets :: proc(path: string, opts: Options, targets: bit_set[Target]) {
        for target in targets {
            opt := opts
            opt.target = target
            _compile(path, opt)
        }
    }

    _compile :: proc(path: string, opts: Options) {
        path := path
        path = os.get_absolute_path(path, context.temp_allocator) or_else path
        res, ok := compile_from_path(path, opts = opts)
        if !ok {
            log.error("Failed to compile: ", path)
            os.exit(1)
        }
        out_path, err := os.join_filename(path, get_target_file_ext(opts.target), context.temp_allocator)
        if err != nil {
            log.error("Failed to join filenames:", err)
            os.exit(1)
        }
        err = os.write_entire_file(out_path, res)
        if err != nil {
            log.error("Failed to write file", out_path)
            os.exit(1)
        }
    }
}
