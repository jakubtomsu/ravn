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
        path:   string `args:"pos=0,required"`,
        data:   bool,
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
}