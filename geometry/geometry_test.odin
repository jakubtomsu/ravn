// Overlap tests
package raven_geometry

import "base:intrinsics"
import "core:math/linalg"


// MARK: Point

@(require_results)
test_point_vs_aabb :: proc "contextless" (pos: [3]f32, min, max: [3]f32) -> bool {
    return  pos.x >= min.x &&
            pos.x <= max.x &&
            pos.y >= min.y &&
            pos.y <= max.y &&
            pos.z >= min.z &&
            pos.z <= max.z
}

@(require_results)
test_point_vs_aabb_simd_single :: proc "contextless" (pos: #simd[4]f32, min, _max: #simd[4]f32) -> bool {
    return 0 != intrinsics.simd_reduce_and(
        (intrinsics.simd_lanes_ge(pos, min) &
        intrinsics.simd_lanes_le(pos, _max)) |
        {0, 0, 0, max(u32)}
    )
}

@(require_results)
test_point_vs_sphere :: proc "contextless" (pos: [3]f32, center: [3]f32, rad: f32) -> bool {
    return linalg.length2(pos - center) <= rad * rad
}

@(require_results)
test_point_vs_capsule :: proc "contextless" (pos: [3]f32, points: [2][3]f32, rad: f32) -> bool {
    dist_sq := get_line_dist_sq(pos, points)
    return dist_sq <= rad * rad
}


// MARK: Sphere

@(require_results)
test_sphere_vs_sphere :: proc "contextless" (pos_a: [3]f32, rad_a: f32, pos_b: [3]f32, rad_b: f32) -> bool {
    rad := rad_a + rad_b
    return linalg.length2(pos_a - pos_b) <= rad * rad
}

@(require_results)
test_sphere_vs_box :: proc "contextless" (pos: [3]f32, rad: f32, center, extent: [3]f32) -> bool {
    dist_sq := linalg.length2(linalg.abs(pos - center) - extent)
    return dist_sq <= rad * rad
}

@(require_results)
test_sphere_vs_triangle :: proc "contextless" (pos: [3]f32, rad: f32, tri: [3][3]f32) -> bool {
    dist_sq := get_triangle_dist_sq(pos, tri)
    return dist_sq <= rad * rad
}


// AABB

@(require_results)
test_aabb_vs_aabb :: proc "contextless" (a_min, a_max: [3]f32, b_min, b_max: [3]f32) -> bool {
    return  a_max[0] >= b_min[0] &&
            a_min[0] <= b_max[0] &&
            a_max[1] >= b_min[1] &&
            a_min[1] <= b_max[1] &&
            a_max[2] >= b_min[2] &&
            a_min[2] <= b_max[2]
}
