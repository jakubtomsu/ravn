package raven_geometry

import "base:intrinsics"
import "core:math/linalg"

@(require_results)
get_triangle_dist :: proc "contextless" (pos: [3]f32, v1: [3]f32, v2: [3]f32, v3: [3]f32) -> (result: f32) {
    return intrinsics.sqrt(get_triangle_dist_sq(pos, v1, v2, v3))
}

@(require_results)
get_triangle_dist_sq :: proc "contextless" (pos: [3]f32, v1: [3]f32, v2: [3]f32, v3: [3]f32) -> (result: f32) {
    // prepare data
    v21 := v2 - v1
    v32 := v3 - v2
    v13 := v1 - v3
    p1 := pos - v1
    p2 := pos - v2
    p3 := pos - v3

    normal := linalg.vector_cross3(v21, v13)

    inside_factor :=
        (linalg.vector_dot(linalg.vector_cross3(v21, normal), p1) >= 0 ? 1 : -1) +
        (linalg.vector_dot(linalg.vector_cross3(v32, normal), p2) >= 0 ? 1 : -1) +
        (linalg.vector_dot(linalg.vector_cross3(v13, normal), p3) >= 0 ? 1 : -1)

    // inside/outside test
    if inside_factor < 2.0 { // Outside
        // 3 edges
        result = min(
            linalg.length2(v21 * clamp(linalg.vector_dot(v21, p1) / linalg.length2(v21), 0.0, 1.0) - p1),
            linalg.length2(v32 * clamp(linalg.vector_dot(v32, p2) / linalg.length2(v32), 0.0, 1.0) - p2),
            linalg.length2(v13 * clamp(linalg.vector_dot(v13, p3) / linalg.length2(v13), 0.0, 1.0) - p3),
        )
    } else {
        // 1 face
        d := linalg.vector_dot(normal, p1)
        result = d * d / linalg.length2(normal)
    }

    return result
}

