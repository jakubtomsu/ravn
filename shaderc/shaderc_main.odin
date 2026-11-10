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
        path:   string `args:"pos=0,required"`,
        target: Target,
    }
    
    args := Args{
        target = DEFAULT_TARGET,
    }
    flags.parse_or_exit(&args, os.args)
    
    opts := DEFAULT_OPTIONS
    
    if !init(args.target) {
        log.error("Failed to init shader compiler")
        os.exit(1)
    }
    defer shutdown()
    
    if os.is_file(args.path) {
        _compile(args.path, opts)
        
    } else if os.is_dir(args.path) {
        append(&opts.include_dirs, args.path)
        
        files, err := os.read_directory_by_path(args.path, 4096, context.temp_allocator)
        if err != nil {
            log.error("Failed to read directory:", err)
            os.exit(1)    
        }
        
        for fi in files {
            if
                strings.ends_with(fi.name, ".vs.hlsl") ||
                strings.ends_with(fi.name, ".ps.hlsl") ||
                strings.ends_with(fi.name, ".cs.hlsl")
            {
                _compile(fi.fullpath, opts)
            }
        }
        
    } else {
        log.error("Path must be file or a directory")
    }
    
    return
    
    _compile :: proc(path: string, opts: Options) {
        path := path
        path = os.get_absolute_path(path, context.temp_allocator) or_else path
        res, ok := compile_from_path(path, opts = opts)
        if !ok {
            log.error("Failed to compile: ", path)
            os.exit(1)
        }
        out_path, err := os.join_filename(path, get_target_file_ext(_state.target), context.temp_allocator)
        if err != nil {
            log.error("Failed to join filenames:", err)
            os.exit(1)
        }
        err = os.write_entire_file(out_path, res.data)
        if err != nil {
            log.error("Failed to write file", out_path)
            os.exit(1)
        }
    }
}
