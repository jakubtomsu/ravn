#+vet explicit-allocators style shadowing unused
package ravn_debugdraw

import "core:math/linalg"


// MARK: Draw simple

line :: proc(pos0: [3]f32, pos1: [3]f32, col: [2][4]u8 = WHITE, time: f32 = 0) {
    buffer_push(&_state.line_buffer,
        data = [2]Vertex{
            { pos = pos0, col = col[0] },
            { pos = pos1, col = col[1] },
        },
        time = time,
    )
}

tri :: proc(
    pos0:   [3]f32,
    pos1:   [3]f32,
    pos2:   [3]f32,
    col:    [3][4]u8 = WHITE,
    time:   f32 = 0,
    fill    := false,
) {
    if fill {
        buffer_push(&_state.tri_buffer,
            data = [3]Vertex{
                { pos = pos0, col = col[0] },
                { pos = pos1, col = col[1] },
                { pos = pos2, col = col[2] },
            },
            time = time,
        )
    } else {
        line(pos0, pos1, {col[0], col[1]}, time = time)
        line(pos1, pos2, {col[1], col[2]}, time = time)
        line(pos2, pos0, {col[2], col[0]}, time = time)
    }
}

box :: proc(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false) {
    shape(fill ? .Filled_Box : .Line_Box, pos, mat, col, time)
}

circle :: proc(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false) {
    shape(fill ? .Filled_Circle : .Line_Circle, pos, mat, col, time)
}

sphere :: proc(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false) {
    shape(fill ? .Filled_Sphere : .Line_Sphere, pos, mat, col, time)
}

hemisphere :: proc(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false) {
    shape(fill ? .Filled_Hemisphere : .Line_Hemisphere, pos, mat, col, time)
}

cone :: proc(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false) {
    shape(fill ? .Filled_Cone : .Line_Cone, pos, mat, col, time)
}

cylinder :: proc(pos: [3]f32, mat: matrix[3, 3]f32 = 1, col := WHITE, time: f32 = 0, fill := false) {
    shape(fill ? .Filled_Cylinder : .Line_Cylinder, pos, mat, col, time)
}

// MARK: Draw util

basis :: proc(pos: [3]f32, mat: matrix[3, 3]f32 = 1, time: f32 = 0, fill := false) {
    line(pos, pos + mat[0], RED  , time)
    line(pos, pos + mat[1], GREEN, time)
    line(pos, pos + mat[2], BLUE , time)
}

aabb :: proc(min: [3]f32, max: [3]f32, col := WHITE, time: f32 = 0, fill := false) {
    box((min + max) * 0.5, linalg.matrix3_scale((max - min) * 0.5), col, time, fill)
}

box_line :: proc(pos0: [3]f32, pos1: [3]f32, rad: f32, col: [4]u8 = WHITE, time: f32 = 0, fill := true) {
    box((pos0 + pos1) * 0.5, calc_line_mat((pos1 - pos0) * 0.5, rad), col, time, fill)
}

cylinder_line :: proc(pos0: [3]f32, pos1: [3]f32, rad: f32, col: [4]u8 = WHITE, time: f32 = 0, fill := true) {
    cylinder((pos0 + pos1) * 0.5, calc_line_mat((pos1 - pos0) * 0.5, rad), col, time, fill)
}

cone_line :: proc(pos0: [3]f32, pos1: [3]f32, rad: f32, col: [4]u8 = WHITE, time: f32 = 0, fill := true) {
    cone((pos0 + pos1) * 0.5, calc_line_mat((pos1 - pos0) * 0.5, rad), col, time, fill)
}

arrow :: proc(pos0: [3]f32, pos1: [3]f32, rad: f32, col: [4]u8 = WHITE, time: f32 = 0, fill := true) {
    dist := linalg.length(pos1 - pos0)
    if dist < 0.0001 {
        return
    }
    r := min(rad, dist)
    dir := (pos1 - pos0) / dist
    mid := pos1 - dir * min(dist, r * 3)
    if dist > r * 3 {
        cylinder_line(pos0, mid, r * 0.3, col, time, fill)
    }
    cone_line(mid, pos1, r, col, time, fill)
}

grid :: proc(
    pos:        [3]f32 = 0,
    axis_a:     [3]f32 = {1, 0, 0},
    axis_b:     [3]f32 = {0, 0, 1},
    col:        [2][4]u8 = {WHITE, LIGHT_GRAY},
    segments:   [2]i32 = 5,
    time:       f32 = 0,
) {
    for i in -segments.x..=segments.x {
        line(
            pos + axis_a * f32(i) - axis_b * f32(segments.y),
            pos + axis_a * f32(i) + axis_b * f32(segments.y),
            col = i %% 10 == 0 ? col[0] : col[1],
            time = time,
        )
    }

    for i in -segments.y..=segments.y {
        line(
            pos + axis_b * f32(i) - axis_a * f32(segments.x),
            pos + axis_b * f32(i) + axis_a * f32(segments.x),
            col = i %% 10 == 0 ? col[0] : col[1],
            time = time,
        )
    }
}

// Y is "forward"
calc_line_mat :: proc(dir: [3]f32, rad: [2]f32) -> (result: matrix[3, 3]f32) {
    result[1] = dir
    temp: [3]f32 = (abs(dir.x) + abs(dir.z)) < 0.0001 ? {1, 0, 0} : {0, 1, 0}
    result[0] = linalg.normalize0(linalg.cross(temp, dir))
    result[2] = linalg.normalize0(linalg.cross(result[0], result[1]))
    result[0] *= rad.x
    result[2] *= rad.y
    return result
}

shape :: proc(
    kind:   Shape_Kind,
    pos:    [3]f32,
    mat:    matrix[3, 3]f32 = 1,
    col:    [4]u8 = WHITE,
    time:   f32 = 0,
) {
    buffer_push(&_state.shape_buffers[kind], make_shape_inst(
        pos = pos,
        mat = mat,
        col = col,
    ), time = time)
}

make_shape_inst :: proc(
    pos:    [3]f32,
    mat:    matrix[3, 3]f32,
    col:    [4]u8,
) -> Shape_Instance {
    cols: [3][4]f32
    cols[0].xyz = mat[0]
    cols[1].xyz = mat[1]
    cols[2].xyz = mat[2]
    return {
        pos = pos,
        col = col,
        mat_x = cast([4]f16)cols[0],
        mat_y = cast([4]f16)cols[1],
        mat_z = cast([4]f16)cols[2],
    }
}