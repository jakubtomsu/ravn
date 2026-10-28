package ravn_scene

import "core:fmt"
import "core:os"

// Dump util
main :: proc() {
    if len(os.args) < 2 {
        fmt.println("Error: invalid arguments")
        os.exit(1)
    }

    scene, err := load(os.args[1])
    if err != nil {
        fmt.println("Error:", err)
        os.exit(1)
    }

    fmt.printf("Scene %q = ", os.args[1])
    fmt.println(to_string(scene, include_data = true))
}