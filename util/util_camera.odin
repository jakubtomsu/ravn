package ravn_util

import "core:math/linalg"
import "core:math"

Camera :: struct {
    pos:        [3]f32,
    rot:        quaternion128,
    // View to clip transform.
    // NDC box is -1..1 on X and Y, and 0..1 on Z axis.
    projection: matrix[4, 4]f32,
}

FRUSTUM_FAR_PLANE_INDEX :: 5

Frustum :: struct {
    planes:     [6][4]f32, // xyz normal, w offset
    corners:    [8][3]f32,
    bounds_min: [3]f32,
    bounds_max: [3]f32,
}


@(require_results)
make_perspective_3d_camera :: proc(screen: [2]f32, pos: [3]f32, rot: quaternion128, fov: f32 = math.PI * 0.5) -> Camera {
    return {
        pos = pos,
        rot = rot,
        projection = perspective_projection(
            screen,
            fov = clamp(fov, 0.00001, math.PI * 0.99),
        ),
    }
}

@(require_results)
make_orthographic_3d_camera :: proc(screen: [2]f32, pos: [3]f32, rot: quaternion128, fov: f32 = 1) -> Camera {
    aspect := screen.x / screen.y
    return {
        pos = pos,
        rot = rot,
        projection = orthographic_projection(
            top = fov,
            bottom = -fov,
            left = -fov * aspect,
            right = fov * aspect,
            near = 1000.0, // Reverse Z!
            far = 0.01,
        ),
    }
}

@(require_results)
make_2d_camera :: proc(screen: [2]f32, pos: [3]f32 = 0, fov: [2]f32 = 1.0, angle: f32 = 0) -> Camera {
    return {
        pos = pos,
        rot = linalg.quaternion_angle_axis_f32(angle, {0, 0, 1}),
        projection = orthographic_projection(
            left  = -fov.x * screen.x * 0.5,
            right = fov.x * screen.x * 0.5,
            top = fov.y * screen.y * 0.5,
            bottom = -fov.y * screen.y * 0.5,
            near = 1,
            far = 0,
        ),
    }
}

@(require_results)
make_screen_camera :: proc(screen: [2]f32, pos: [3]f32 = 0) -> Camera {
    return {
        pos = pos + {0, 0, -1},
        rot = 1,
        projection = orthographic_projection(
            left = 0,
            right = screen.x,
            top = 0,
            bottom = screen.y,
            near = 2,
            far = 0,
        ),
    }
}

orthographic_projection :: proc(left, right, top, bottom: f32, near: f32 = 0.01, far: f32 = 1000.0) -> (result: matrix[4, 4]f32) {
    // D3D11, LH 0..1 NDC
    // https://learn.microsoft.com/en-us/windows/win32/direct3d9/d3dxmatrixorthooffcenterlh

    result[0, 0] = 2 / (right - left)
    result[1, 1] = 2 / (top - bottom)
    result[2, 2] = 1 / (far - near)
    result[0, 3] = (left + right) / (left - right)
    result[1, 3] = (top + bottom) / (bottom - top)
    result[2, 3] = near / (near - far)
    result[3, 3] = 1

    return result
}

// left handed reverse Z
// https://iolite-engine.com/blog_posts/reverse_z_cheatsheet
// NOTE: use Greater depth comparison!
perspective_projection :: proc(screen: [2]f32, fov: f32, near: f32 = 0.01, far: f32 = 1000.0) -> (result: matrix[4, 4]f32) {
    assert(fov > 0)
    assert(screen.x > 0)
    assert(screen.y > 0)

    aspect := screen.x / screen.y
    tan_half_fovy := math.tan(0.5 * fov)
    result[0, 0] = 1.0 / (tan_half_fovy * aspect)
    result[1, 1] = 1.0 / tan_half_fovy
    result[2, 2] = -near / (far - near)
    result[2, 3] = (far * near) / (far - near)
    result[3, 2] = 1

    return result
}

calc_camera_world_to_view_matrix :: proc(camera: Camera) -> (result: matrix[4, 4]f32) {
    result =
        linalg.matrix4_from_quaternion_f32(linalg.quaternion_inverse(camera.rot)) *
        linalg.matrix4_translate_f32(-camera.pos)
    return result
}

calc_camera_world_to_clip_matrix :: proc(camera: Camera) -> (result: matrix[4, 4]f32) {
    result = camera.projection * calc_camera_world_to_view_matrix(camera)
    return result
}

calc_camera_frustum :: proc(cam: Camera) -> Frustum {
    mvp := calc_camera_world_to_clip_matrix(cam)
    inv := linalg.matrix4_inverse_f32(mvp)
    return calc_matrix_frustum(inv)
}

calc_matrix_frustum :: proc(clip_to_world: matrix[4, 4]f32) -> (result: Frustum) {
    // https://iquilezles.org/articles/frustumcorrect/
    // https://iquilezles.org/articles/frustum/

    fru := [8][4]f32{
        0 = clip_to_world * [4]f32{-1, -1,  0, 1.0},
        1 = clip_to_world * [4]f32{+1, -1,  0, 1.0},
        2 = clip_to_world * [4]f32{-1, +1,  0, 1.0},
        3 = clip_to_world * [4]f32{+1, +1,  0, 1.0},
        4 = clip_to_world * [4]f32{-1, -1, +1, 1.0},
        5 = clip_to_world * [4]f32{+1, -1, +1, 1.0},
        6 = clip_to_world * [4]f32{-1, +1, +1, 1.0},
        7 = clip_to_world * [4]f32{+1, +1, +1, 1.0},
    }

    for p, i in fru {
        result.corners[i] = p.xyz / p.w
    }

    result.bounds_min = result.corners[0]
    result.bounds_max = result.corners[0]
    for p in result.corners[1:] {
        result.bounds_min = linalg.min(result.bounds_min, p)
        result.bounds_max = linalg.max(result.bounds_max, p)
    }

    center: [3]f32
    for p in result.corners {
        center += p
    }
    center *= 1.0 / 8.0

    result.planes = {
        _tri_plane(center, result.corners[4], result.corners[6], result.corners[5]),
        _tri_plane(center, result.corners[0], result.corners[4], result.corners[1]),
        _tri_plane(center, result.corners[2], result.corners[3], result.corners[6]),
        _tri_plane(center, result.corners[0], result.corners[2], result.corners[4]),
        _tri_plane(center, result.corners[1], result.corners[5], result.corners[3]),
        _tri_plane(center, result.corners[0], result.corners[1], result.corners[2]),
    }

    return result

    _tri_plane :: proc(center: [3]f32, a, b, c: [3]f32) -> [4]f32 {
        normal := linalg.normalize0(linalg.cross(b - a, c - a))

        if linalg.dot(a - center, normal) < 0 {
            normal = -normal
        }

        return {
            normal.x,
            normal.y,
            normal.z,
            linalg.dot(normal, a),
        }
    }
}

is_box_in_frustum :: proc(fru: Frustum, pos: [3]f32, rad: [3]f32) -> bool #no_bounds_check {
    EPS :: 1

    bounds_min := fru.bounds_min - rad - EPS
    bounds_max := fru.bounds_max + rad + EPS

    if pos.x < bounds_min.x ||
       pos.y < bounds_min.y ||
       pos.z < bounds_min.z ||
       pos.x > bounds_max.x ||
       pos.y > bounds_max.y ||
       pos.z > bounds_max.z
    {
        return false
    }

    for plane in fru.planes {
        rad_on_normal := rad.x * abs(plane.x) + rad.y * abs(plane.y) + rad.z * abs(plane.z)
        dist := linalg.dot(plane.xyz, pos) - plane.w - rad_on_normal
        if dist > EPS {
            return false
        }
    }

    return true
}

is_sphere_in_frustum :: proc(fru: Frustum, pos: [3]f32, rad: f32) -> bool #no_bounds_check {
    EPS :: 1

    bounds_min := fru.bounds_min - rad - EPS
    bounds_max := fru.bounds_max + rad + EPS

    if pos.x < bounds_min.x ||
       pos.y < bounds_min.y ||
       pos.z < bounds_min.z ||
       pos.x > bounds_max.x ||
       pos.y > bounds_max.y ||
       pos.z > bounds_max.z
    {
        return false
    }

    for plane in fru.planes {
        dist := linalg.dot(plane.xyz, pos) - plane.w - rad
        if dist > EPS {
            return false
        }
    }

    return true
}

// Returns the ray direction.
screen_to_world_ray :: proc(pos: [2]f32, cam: Camera, screen_size: [2]f32) -> [3]f32 {
    cam_mvp := calc_camera_world_to_clip_matrix(cam)
    cam_inv := linalg.matrix4_inverse_f32(cam_mvp)

    p := pos

    p.x = (p.x / f32(screen_size.x)) * 2.0 - 1.0
    p.y = 1.0 - 2.0 * (p.y / f32(screen_size.y))

    p0 := cam_inv * [4]f32{p.x, p.y, 0.0, 1.0}
    p1 := cam_inv * [4]f32{p.x, p.y, 1.0, 1.0}
    p0.xyz /= p0.w
    p1.xyz /= p1.w

    return linalg.normalize0(p1.xyz - p0.xyz)
}

