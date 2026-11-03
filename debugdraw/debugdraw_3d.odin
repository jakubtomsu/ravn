#+vet explicit-allocators style shadowing unused
package ravn_debugdraw

import "core:math/linalg"


// MARK: Draw simple

line :: proc(
    pos0:   [3]f32,
    pos1:   [3]f32,
    col:    [2][4]u8 = WHITE,
    time:   f32 = 0,
) {
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