package ravn

Curve_Kind :: enum u8 {
    Linear,
    Bezier,
    Hermite,
    Catmull_Rom,
    B_Spline,
}

curve_cubic :: proc(points: [4]$T, t: f32, m: matrix[4, 4]f32) -> (result: T) {
    t2 := t * t
    t3 := t2 * t
    result =
        points[0] * (m[0][3] * t3 + m[0][2] * t2 + m[0][1] * t + m[0][0]) +
        points[1] * (m[1][3] * t3 + m[1][2] * t2 + m[1][1] * t + m[1][0]) +
        points[2] * (m[2][3] * t3 + m[2][2] * t2 + m[2][1] * t + m[2][0]) +
        points[3] * (m[3][3] * t3 + m[3][2] * t2 + m[3][1] * t + m[3][0])
    return result
}

// Shapes, fonts, vector graphics.
// C0/C1 continuity.
// Manual tangents.
curve_bezier :: proc(points: [4]$T, t: f32) -> (result: T) {
    // t2 := t * t
    // t3 := t2 * t
    // result =
    //     points[0] * (-1 * t3 + 3 * t2 - 3 * t + 1) +
    //     points[1] * (+3 * t3 - 6 * t2 + 3 * t + 0) +
    //     points[2] * (-3 * t3 + 3 * t2 + 0 * t + 0) +
    //     points[3] * (+1 * t3 + 0 * t2 + 0 * t + 0)
    // return result
    M :: matrix[4, 4]f32{
        +1, +0, +0, +0,
        -3, +3, +0, +0,
        +3, -6, +3, +0,
        -1, +3, -3, +1,
    }
    return #force_inline curve_cubic(points, t, M)
}

// Animation, physics sim, interpolation.
// C0/C1 continuity.
curve_hermite_points :: proc(points: [4]$T, t: f32) -> T {
    values := [4]T{points[0], points[1] - points[0], points[3], points[3] - points[2]}
    return curve_hermite_tangents(values, t)
}

// Based on two points with velocities.
// Explicit tangents.
// Values are [p0, v0, p1, v1]
curve_hermite_tangents :: proc(values: [4]$T, t: f32) -> T {
    M :: matrix[4, 4]f32{
        +1, +0, +0, +0,
        +0, +1, +0, +0,
        -3, -2, +3, -1,
        +2, +1, -2, +1,
    }
    return #force_inline curve_cubic(values, t, M)
}

curve_hermite :: proc(pos0, vel0, pos1, vel1: $T, t: f32) -> T {
    return curve_hermite_tangents([4]T{pos0, vel0, pos1, vel1}, t)
}


// Animation and paths.
// C1 continuity.
// Automatic tangents.
curve_catmull_rom :: proc(points: [4]$T, t: f32) -> (result: T) {
    M :: matrix[4, 4]f32{
        +0, +2, +0, +0,
        -1, +0, +1, +0,
        +2, -5, +4, -1,
        -1, +3, -3, +1,
    }
    return #force_inline curve_cubic(points, t, M) * 0.5
}

// Catmull rom with configurable scale factor.
curve_cardinal :: proc(points: [4]$T, t: f32, scale: f32) {
    m := matrix[4, 4]f32{
        0, 1, 0, 0,
        -s, 0, s, 0,
        2 * s, s - 3, 3 - 2 * s, -s,
        -s, 2 - s, s - 2, s,
    }
    return #force_inline curve_cubic(points, t, m)
}

// Curvature-sensitive shapes, animations, camera paths.
// C2 continuity.
// Automatic tangents.
curve_b_spline :: proc(points: [4]$T, t: f32) -> (result: T) {
    M :: matrix[4, 4]f32{
        +1, +4, +1, +0,
        -3, +0, +3, +0,
        +3, -6, +3, +0,
        -1, +3, -3, +1,
    }
    return #force_inline curve_cubic(points, t, M) * (1.0 / 6.0)
}

curve_sample :: proc(curve: Curve_Kind, points: [4]$T, t: f32) -> T {
    switch curve {
    case .Linear:
    case .Bezier:
        return curve_bezier(points, t)
    case .Hermite:
        return curve_hermite_points(points, t)
    case .Catmull_Rom:
        return curve_catmull_rom(points, t)
    case .B_Spline:
        return curve_b_spline(points, t)
    }
    return points[0]
}

spline_sample_linear :: proc(points: []$T, t: f32) -> T {
    t_segment := fract(t)
    i_base := max(0, int(floor(t)))
    i0 := min(i_base + 0, len(points))
    i1 := min(i_base + 1, len(points))
    v0 := points[i0]
    v1 := points[i1]
    return lerp(v0, v1, t_segment)
}
