package ravn_geometry

import "base:intrinsics"
import "core:math/linalg"
import "../base"

// https://iquilezles.org/articles/distgradfunctions3d/
// https://iquilezles.org/articles/distfunctions/
// https://iquilezles.org/articles/triangledistance/

@(require_results)
get_sphere_dist_sq :: proc "contextless" (pos: [3]f32, center: [3]f32, rad: f32) -> f32 {
    return linalg.length2(pos - center) - rad * rad
}

@(require_results)
get_sphere_dist :: proc "contextless" (pos: [3]f32, center: [3]f32, rad: f32) -> f32 {
    return linalg.length(pos - center) - rad
}

@(require_results)
get_sphere_dist_grad :: proc "contextless" (pos: [3]f32, center: [3]f32, rad: f32) -> (dist: f32, grad: [3]f32) {
    rel := pos - center
    dist = linalg.length(rel)
    grad = dist < 1e-6 ? {0, 1, 0} : rel / dist
    return dist - rad, grad
}

@(require_results)
get_box_dist :: proc "contextless" (pos: [3]f32, center: [3]f32, rad: [3]f32) -> f32 {
    q := linalg.abs(pos - center) - rad
    m := max(q.x, q.y, q.z)
    return linalg.vector_length(linalg.max(q, 0.0)) + min(m, 0.0)
}

@(require_results)
get_box_dist_grad :: proc "contextless" (pos: [3]f32, center: [3]f32, rad: [3]f32) -> (dist: f32, grad: [3]f32) {
    rel := pos - center
    w := linalg.abs(rel) - rad
    g := max(w.x, w.y, w.z)
    q := linalg.max(w, 0.0)
    l := linalg.vector_length(q)
    f: [3]f32
    if g > 0 {
        dist = l
        grad = q / l
    } else {
        dist = g
        grad = {
            w.x == g ? 1.0 : 0.0,
            w.y == g ? 1.0 : 0.0,
            w.z == g ? 1.0 : 0.0,
        }
    }
    grad *= linalg.sign(rel)
    return dist, grad
}


// Capsule
@(require_results)
get_line_dist :: proc "contextless" (pos: [3]f32, points: [2][3]f32) -> f32 {
    return intrinsics.sqrt(get_line_dist_sq(pos, points))
}

@(require_results)
get_line_dist_sq :: proc "contextless" (pos: [3]f32, points: [2][3]f32) -> f32 {
    pa := pos - points[0]
    ba := points[1] - points[0]
    h := clamp(linalg.vector_dot(pa, ba) / linalg.vector_length2(ba), 0.0, 1.0)
    return linalg.vector_length2(pa - ba * h)
}

// Capsule
@(require_results)
get_line_dist_grad :: proc "contextless" (pos: [3]f32,  points: [2][3]f32) -> (dist: f32, grad: [3]f32) {
    pa := pos - points[0]
    ba := points[1] - points[0]
    h := clamp(linalg.vector_dot(pa, ba) / linalg.vector_length2(ba), 0.0, 1.0)
    q := pa - h * ba
    d := linalg.vector_length(q)
    grad = d > 0 ? q / d : 0
    return d, grad
}

@(require_results)
get_triangle_dist :: proc "contextless" (pos: [3]f32, tri: [3][3]f32) -> (dist: f32) {
    return intrinsics.sqrt(get_triangle_dist_sq(pos, tri))
}

@(require_results)
get_triangle_dist_sq :: proc "contextless" (pos: [3]f32, tri: [3][3]f32) -> (dist: f32) {
    // prepare data
    v10 := tri[1] - tri[0]
    v23 := tri[2] - tri[1]
    v02 := tri[0] - tri[2]
    p1 := pos - tri[0]
    p2 := pos - tri[1]
    p3 := pos - tri[2]

    normal := linalg.vector_cross3(v10, v02)

    inside_factor :=
        (linalg.vector_dot(linalg.vector_cross3(v10, normal), p1) >= 0 ? 1 : -1) +
        (linalg.vector_dot(linalg.vector_cross3(v23, normal), p2) >= 0 ? 1 : -1) +
        (linalg.vector_dot(linalg.vector_cross3(v02, normal), p3) >= 0 ? 1 : -1)

    // inside/outside test
    if inside_factor < 2.0 { // Outside
        // 3 edges
        dist = min(
            linalg.vector_length2(v10 * clamp(linalg.vector_dot(v10, p1) / linalg.vector_length2(v10), 0.0, 1.0) - p1),
            linalg.vector_length2(v23 * clamp(linalg.vector_dot(v23, p2) / linalg.vector_length2(v23), 0.0, 1.0) - p2),
            linalg.vector_length2(v02 * clamp(linalg.vector_dot(v02, p3) / linalg.vector_length2(v02), 0.0, 1.0) - p3),
        )
    } else {
        // 1 face
        d := linalg.vector_dot(normal, p1)
        dist = d / linalg.vector_length2(normal)
    }

    return dist
}


@(require_results)
get_triangle_dist_grad :: proc "contextless" (pos: [3]f32, tri: [3][3]f32) -> (dist: f32, grad: [3]f32) {
    // prepare data
    v10 := tri[1] - tri[0]
    v23 := tri[2] - tri[1]
    v02 := tri[0] - tri[2]
    p1 := pos - tri[0]
    p2 := pos - tri[1]
    p3 := pos - tri[2]

    normal := linalg.vector_cross3(v10, v02)

    inside_factor :=
        (linalg.vector_dot(linalg.vector_cross3(v10, normal), p1) >= 0 ? 1 : -1) +
        (linalg.vector_dot(linalg.vector_cross3(v23, normal), p2) >= 0 ? 1 : -1) +
        (linalg.vector_dot(linalg.vector_cross3(v02, normal), p3) >= 0 ? 1 : -1)

    // inside/outside test
    if inside_factor < 2.0 { // Outside
        // 3 edges

        d12, g12 := get_line_dist_grad(pos, {tri[0], tri[1]})
        d13, g13 := get_line_dist_grad(pos, {tri[0], tri[2]})
        d23, g23 := get_line_dist_grad(pos, {tri[1], tri[2]})

        dist = min(d12, d13, d23)

        if dist == d12 {
            grad = g12
        } else if dist == d13 {
            grad = g13
        } else if dist == d23 {
            grad = g23
        }

    } else {
        // 1 face
        d := linalg.vector_dot(normal, p1)
        normal_len2 := linalg.vector_length2(normal)
        grad = normal * (1.0 / intrinsics.sqrt(normal_len2))
        grad = d >= 0 ? grad : -grad
        dist = d * (1.0 / normal_len2)
    }

    return dist, grad
}

