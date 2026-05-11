package ravn_geometry

import "core:math/linalg"

Voronoi_Feature_Kind :: enum u8 {
    Face,
    Edge,
    Vertex,
}

// Edges: 01, 02, 12
@(require_results)
get_triangle_closest_point :: proc "contextless" (
    pos:            [3]f32,
    tri:            [3][3]f32,
) -> (
    closest:        [3]f32,
    feature_kind:   Voronoi_Feature_Kind,
    feature_index:  i32,
) {
    v01 := tri[1] - tri[0]
    v02 := tri[2] - tri[0]
    v12 := tri[2] - tri[1]
    d1 := linalg.dot(v01, pos - tri[0])
    d2 := linalg.dot(v02, pos - tri[0])
    d3 := linalg.dot(v01, pos - tri[1])
    d4 := linalg.dot(v02, pos - tri[1])
    d5 := linalg.dot(v01, pos - tri[2])
    d6 := linalg.dot(v02, pos - tri[2])

    // Vertices
    if d1 <= 0 && d2 <= 0  do return tri[0], .Vertex, 0
    if d3 >= 0 && d4 <= d3 do return tri[1], .Vertex, 1
    if d6 >= 0 && d5 <= d6 do return tri[2], .Vertex, 2

    // Edges

    vc := d1 * d4 - d3 * d2
    vb := d5 * d2 - d1 * d6
    va := d3 * d6 - d5 * d4

    if vc < 0 && d1 >= 0 && d3 <= 0 {
        v := d1 / (d1 - d3)
        return tri[0] + v * v01, .Edge, 0
    }

    if vb <= 0 && d2 >= 0 && d6 <= 0 {
        w := d2 / (d2 - d6)
        return tri[0] + w * v02, .Edge, 1
    }

    if va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0 {
        w := (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return tri[1] + w * v12, .Edge, 2
    }

    denom := 1.0 / (va + vb + vc)
    v := vb * denom
    w := vc * denom

    return tri[0] + v01 * v + v02 * w, .Face, 0
}
