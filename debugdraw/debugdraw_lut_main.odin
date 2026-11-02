#+vet explicit-allocators shadowing unused
package ravn_debugdraw

import "core:math"
import "core:fmt"

main :: proc() {
    NUM_VERTS :: 16
    fmt.printfln("Circle of %i verts:", NUM_VERTS)
    for i in 0..<NUM_VERTS {
        a := f64(i) * math.TAU / NUM_VERTS
        // fmt.printfln("    %5i, %5i,", quantize_snorm8(math.cos_f64(a)), quantize_snorm8(math.sin_f64(a)))
        fmt.printfln("    %24g, %24g,", math.cos_f64(a), math.sin_f64(a))
    }

    return

    // input -1..1
    // output dual -1 representation
    quantize_snorm8 :: proc(val: f64) -> i8 {
        return i8(math.round(clamp(val, -1, 1) * 127))
    }
}
