package raven_geometry

import "base:intrinsics"
import "core:math/linalg"

// https://iquilezles.org/articles/distgradfunctions3d/

@(require_results)
get_box_dist :: proc "contextless" (p: [3]f32, b: [3]f32) -> f32 {
  q := linalg.abs(p) - b
  m := max(q.x, q.y, q.z)
  return m > 0 ? linalg.length(q) : m
}

@(require_results)
get_box_dist_grad :: proc "contextless" (p: [3]f32, b: [3]f32) -> (dist: f32, grad: [3]f32) {
    w := linalg.abs(p) - b
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
    grad *= linalg.sign(p)
    return dist, grad
}


// Capsule
@(require_results)
get_line_dist :: proc "contextless" (p: [3]f32, a: [3]f32, b: [3]f32) -> f32 {
  pa := p - a
  ba := b - a
  h := clamp(linalg.vector_dot(pa, ba) / linalg.vector_length2(ba), 0.0, 1.0)
  return linalg.vector_length(pa - ba * h)
}

// Capsule
@(require_results)
get_line_dist_grad :: proc "contextless" (p: [3]f32,  a: [3]f32, b: [3]f32) -> (dist: f32, grad: [3]f32) {
    ba := b - a
    pa := p - a
    h := clamp(linalg.vector_dot(pa, ba) / linalg.vector_length2(ba), 0.0, 1.0)
    q := pa - h * ba
    d := linalg.vector_length(q)
    return d, q / d
}

@(require_results)
get_triangle_dist :: proc "contextless" (pos: [3]f32, v1: [3]f32, v2: [3]f32, v3: [3]f32) -> (dist: f32) {
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
        dist = min(
            linalg.vector_length2(v21 * clamp(linalg.vector_dot(v21, p1) / linalg.vector_length2(v21), 0.0, 1.0) - p1),
            linalg.vector_length2(v32 * clamp(linalg.vector_dot(v32, p2) / linalg.vector_length2(v32), 0.0, 1.0) - p2),
            linalg.vector_length2(v13 * clamp(linalg.vector_dot(v13, p3) / linalg.vector_length2(v13), 0.0, 1.0) - p3),
        )
    } else {
        // 1 face
        d := linalg.vector_dot(normal, p1)
        dist = d * d / linalg.vector_length2(normal)
    }

    return intrinsics.sqrt(dist)
}


@(require_results)
get_triangle_dist_grad :: proc "contextless" (pos: [3]f32, v1: [3]f32, v2: [3]f32, v3: [3]f32) -> (dist: f32, grad: [3]f32) {
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
        
        d12, g12 := get_line_dist_grad(pos, v1, v2)
        d13, g13 := get_line_dist_grad(pos, v1, v3)
        d23, g23 := get_line_dist_grad(pos, v2, v3)
        
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
        grad = d > 0 ? normal : -normal
        dist = d / linalg.vector_length2(normal)
    }

    return dist, grad
}

