package ravn_geometry

import "core:math/linalg"

@(require_results)
get_oriented_box_bounds :: proc "contextless" (
    pos: [3]f32,
    rad: [3]f32,
    rot: matrix[3, 3]f32,
) -> (min, max: [3]f32) {
    box_max :=
        linalg.abs(rad.x * rot[0]) +
        linalg.abs(rad.y * rot[1]) +
        linalg.abs(rad.z * rot[2])
    return pos - box_max, pos + box_max
}
