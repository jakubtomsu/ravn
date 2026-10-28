package ravn_scene

import "core:fmt"
import "core:os"
import "core:flags"

// Dump util
main :: proc() {
    Args :: struct {
        exec:   string `args:"pos=0,required"`,
        path:   string `args:"pos=1,required"`,
        data:   bool,
    }

    args: Args
    args_err := flags.parse(&args, os.args)
    if args_err != nil {
        fmt.println("Error parsing args: ", args_err)
        os.exit(2)
    }

    scene, err := load(args.path)
    if err != nil {
        fmt.println("Error:", err)
        os.exit(1)
    }

    fmt.printf("Scene %q = ", args.path)
    fmt.println(to_string(scene, include_data = args.data))
}