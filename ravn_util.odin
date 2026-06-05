// Gameplay utilities.
// WARNING: all of this will likely be moved to a separate utils package.
package ravn

import "core:math"
import "core:math/linalg"
import "base:intrinsics"
import "base/ufmt"
import "base"

log_err :: base.log_err
log_warn :: base.log_warn
log_info :: base.log_info
log_debug :: base.log_debug
log_dump :: base.log_dump
log :: base.log

// TODO: random vector utilities etc
// TODO: 1d/2d/3d hashing

// TODO: non ugly colors? paletted? more shades?
WHITE           :: [4]f32{1, 1, 1, 1}
BLACK           :: [4]f32{0, 0, 0, 1}
TRANSPARENT     :: [4]f32{1, 1, 1, 0}
GRAY            :: [4]f32{0.5, 0.5, 0.5, 1}
DARK_GRAY       :: [4]f32{0.25, 0.25, 0.25, 1}
LIGHT_GRAY      :: [4]f32{0.75, 0.75, 0.75, 1}
RED             :: [4]f32{1, 0, 0, 1}
DARK_RED        :: [4]f32{0.5, 0, 0, 1}
LIGHT_RED       :: [4]f32{1, 0.5, 0.5, 1}
GREEN           :: [4]f32{0, 1, 0, 1}
DARK_GREEN      :: [4]f32{0, 0.5, 0, 1}
LIGHT_GREEN     :: [4]f32{0.5, 1, 0.5, 1}
BLUE            :: [4]f32{0, 0, 1, 1}
DARK_BLUE       :: [4]f32{0, 0, 0.5, 1}
LIGHT_BLUE      :: [4]f32{0.5, 0.5, 1, 1}
YELLOW          :: [4]f32{1, 1, 0, 1}
LIGHT_YELLOW    :: [4]f32{1, 1, 0.5, 1}
CYAN            :: [4]f32{0, 1, 1, 1}
DARK_CYAN       :: [4]f32{0, 0.5, 0.5, 1}
LIGHT_CYAN      :: [4]f32{0.5, 1, 1, 1}
PINK            :: [4]f32{1, 0, 1, 1}
DARK_PINK       :: [4]f32{0.5, 0, 0.5, 1}
LIGHT_PINK      :: [4]f32{1, 0.5, 1, 1}
ORANGE          :: [4]f32{1, 0.5, 0, 1}
LIGHT_ORANGE    :: [4]f32{1, 0.75, 0.5, 1}
PURPLE          :: [4]f32{0.5, 0, 1, 1}
DARK_PURPLE     :: [4]f32{0.25, 0, 0.5, 1}
LIGHT_PURPLE    :: [4]f32{0.75, 0.5, 1, 1}

quat_angle_axis :: linalg.quaternion_angle_axis_f32

eprintf :: ufmt.eprintf
eprintfln :: ufmt.eprintfln
tprintf :: ufmt.tprintf

@(require_results)
deg :: #force_inline proc "contextless" (degrees: f32) -> (radians: f32) {
    return degrees * math.RAD_PER_DEG
}

@(require_results)
lerp :: proc "contextless" (a, b: $T, t: f32) -> T where !intrinsics.type_is_quaternion(T) {
    return a * (1 - t) + b * t
}

// Exponential lerp. Multiply rate by delta to get frame rate independent interpolation
@(require_results)
lexp :: proc "contextless" (a, b: $T, rate: f32) -> T {
    return lerp(b, a, approx_nexp(rate))
}

@(require_results)
nlerp :: proc "contextless" (a, b: $T, t: f32) -> T {
    return linalg.normalize0(lerp(a, b, t))
}

@(require_results)
nlexp :: proc "contextless" (a, b: $T, rate: f32) -> T {
    return nlerp(b, a, approx_nexp(rate))
}

@(require_results)
move_towards :: proc "contextless" (x, target: $T, rate: f32) -> T {
    if abs(x - target) < rate {
        return target
    } else {
        return x + rate * (x < target ? 1 : -1)
    }
}

@(require_results)
fade :: #force_inline proc "contextless" (alpha: f32) -> [4]f32 {
    return {1, 1, 1, alpha}
}

@(require_results)
gray :: #force_inline proc "contextless" (val: f32) -> [4]f32 {
    return {val, val, val, 1}
}

@(require_results)
addz :: #force_inline proc "contextless" (v: [2]f32, z: f32 = 0.0) -> [3]f32 {
    return {v.x, v.y, z}
}

@(require_results)
nsin :: proc "contextless" (x: f32) -> f32 {
    return 0.5 + 0.5 * math.sin_f32(x * math.PI * 2)
}

@(require_results)
vcast :: proc "contextless" ($T: typeid, v: [$N]$E) -> (result: [N]T)
    where intrinsics.type_is_integer(E) || intrinsics.type_is_float(E)
{
    for elem, i in v {
        result[i] = cast(T)elem
    }
    return result
}

@(require_results)
int_cast :: proc($Dst: typeid, v: $Src) -> Dst where intrinsics.type_is_integer(Dst), intrinsics.type_is_integer(Src) {
    assert(v == Src(Dst(v)), "Safe integer cast failed")
    return cast(Dst)v
}

// Counter-clockwise. Negate to do clockwise.
@(require_results)
rot90 :: #force_inline proc "contextless" (v: [2]$T) -> [2]T {
    return {-v.y, v.x}
}


// Returns value in 0..1 range.
// Same as remap(t, a, b, 0, 1)
@(require_results)
unlerp :: proc "contextless" (a, b: f32, x: f32) -> f32 {
    return (x - a) / (b - a)
}

// Linearly transform x from range a0..a1 to b0..b1
@(require_results)
remap :: proc "contextless" (x, a0, a1, b0, b1: f32) -> f32 {
    return ((x - a0) / (a1 - a0)) * (b1 - b0) + b0
}

@(require_results)
remap_clamped :: #force_inline proc "contextless" (x, a0, a1, b0, b1: f32) -> f32 {
    return remap(clamp(x, a0, a1), a0, a1, b0, b1)
}

@(require_results)
smoothstep :: proc "contextless" (edge0, edge1, x: f32) -> f32 {
    t := clamp((x - edge0) / (edge1 - edge0), 0.0, 1)
    return t * t * (3.0 - 2.0 * t)
}

@(require_results)
luminance :: proc "contextless" (rgb: [3]f32) -> f32 {
    return linalg.dot(rgb, [3]f32{0.2126, 0.7152, 0.0722})
}

floor :: proc {
    floor_f32,
    floor_vec,
}

@(require_results)
floor_vec :: proc (x: [$N]f32) -> [N]f32 where N <= 4 {
    return transmute([N]f32)intrinsics.simd_floor(transmute(#simd[N]f32)x)
}

@(require_results)
floor_f32 :: proc (x: f32) -> f32 {
    return transmute(f32)intrinsics.simd_floor(transmute(#simd[1]f32)x)
}

// RGB only!
@(require_results)
hex_color :: proc "contextless" (hex: u32) -> [4]f32 {
    bytes := transmute([4]u8)hex

    return {
        f32(bytes[2]) / 255.0,
        f32(bytes[1]) / 255.0,
        f32(bytes[0]) / 255.0,
        1.0,
    }
}

// Oklab lerp - Better color gradients than regular lerp()
@(require_results)
oklerp :: proc "contextless" (a, b: [4]f32, t: f32) -> (result: [4]f32) {
    // https://bottosson.github.io/posts/oklab
    // https://www.shadertoy.com/view/ttcyRS
    CONE_TO_LMS :: matrix[3, 3]f32{0.4121656120, 0.2118591070, 0.0883097947, 0.5362752080, 0.6807189584, 0.2818474174, 0.0514575653, 0.1074065790, 0.6302613616}
    LMS_TO_CONE :: matrix[3, 3]f32{4.0767245293, -1.2681437731, -0.0041119885, -3.3072168827, 2.6093323231, -0.7034763098, 0.2307590544, -0.3411344290, 1.7068625689}

    // rgb to cone (arg of pow can't be negative)
    lms_a := linalg.pow(CONE_TO_LMS * a.rgb, 1 / 3.0)
    lms_b := linalg.pow(CONE_TO_LMS * b.rgb, 1 / 3.0)
    lms := lerp(lms_a, lms_b, t)
    // gain in the middle (no oaklab anymore, but looks better?)
    // lms *= 1+0.2*h*(1-h);
    // cone to rgb
    result.rgb = LMS_TO_CONE * (lms * lms * lms)
    result.a = lerp(a.a, b.a, t)
    return result
}

// 0 -> Red, 0.5 -> Blue, 1 -> Green
@(require_results)
heatmap_color :: proc(val: f32) -> (result: [4]f32) {
    result.g = smoothstep(0.5, 0.8, val)
    if (val > 0.5) {
        result.b = smoothstep(1, 0.5, val)
    } else {
        result.b = smoothstep(0.0, 0.5, val)
    }
    result.r = smoothstep(1, 0.0, val)
    result.a = 1
    return result
}

// ZXY order for first-person view.
@(require_results)
euler_rot :: proc(angles: [3]f32) -> quaternion128 {
    return linalg.quaternion_from_euler_angle_y_f32(angles.y) *
           linalg.quaternion_from_euler_angle_x_f32(angles.x) *
           linalg.quaternion_from_euler_angle_z_f32(angles.z)
}


// Spring Integration
// Source: http://allenchou.net/2015/04/game-math-precise-control-over-numeric-springing/
// damp: zeta, smoothness halflife
// freq: omega, the oscillation frequency
spring :: proc "contextless" (x, v: ^$T, x_target: T, damp: f32, freq: f32, delta: f32)
    where intrinsics.type_is_float(T) || (intrinsics.type_is_array(T) && intrinsics.type_is_float(intrinsics.type_elem_type(T)))
{
    x_temp := x^
    v_temp := v^
    f := 1.0 + 2.0 * delta * damp * freq
    oo := freq * freq
    hoo := delta * oo
    hhoo := delta * hoo
    det_inv := 1.0 / (f + hhoo)
    det_x := f * x_temp + delta * v_temp + hhoo * x_target
    det_v := v_temp + hoo * (x_target - x_temp)
    x^ = det_x * det_inv
    v^ = det_v * det_inv
}

// Utility for springs where X and V are packed in an array.
spring2 :: proc "contextless" (xv: ^[2]$T, x_target: T, damp: f32, freq: f32, delta: f32)
    where intrinsics.type_is_float(T) || (intrinsics.type_is_array(T) && intrinsics.type_is_float(intrinsics.type_elem_type(T)))
{
    spring(&xv[0], &xv[1], x_target = x_target, damp = damp, freq = freq, delta = delta)
}


// https://gist.github.com/jakubtomsu/d25210b55037858c3ed35fe00182f92a
@(require_results)
approx_nexp :: proc "contextless" (x: f32) -> (result: f32) {
    A :: 1.1566406
    C :: 0.53652346
    denom := 1.0 + x * (A + C * x * x)
    return rcp(denom)
}

@(require_results)
rcp :: proc "contextless" (denom: f32) -> (result: f32) {
    // TODO: make this compile on WASM
    // when ODIN_ARCH == .amd64 {
        // return intrinsics.simd_extract(x86._mm_rcp_ss(cast(x86.__m128)denom), 0)
    // } else {
        return 1.0 / denom
    // }
}



//////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Rect
//

@(require_results) rect_make :: proc(min: [2]f32, full_size: [2]f32) -> Rect {
    return {
        min = min,
        max = min + full_size,
    }
}

@(require_results) rect_make_centered :: proc(pos: [2]f32, half_size: [2]f32) -> Rect {
    return {pos - half_size, pos + half_size}
}

@(require_results) rect_center :: proc(r: Rect) -> [2]f32 {
    return (r.min + r.max) * 0.5
}

@(require_results) rect_anchor :: proc(r: Rect, anchor: [2]f32) -> [2]f32 {
    return {lerp(r.min.x, r.max.x, anchor.x), lerp(r.min.y, r.max.y, anchor.y)}
}

@(require_results) rect_full_size :: #force_inline proc(r: Rect) -> [2]f32 {
    return r.max - r.min
}

@(require_results) rect_expand :: proc(r: Rect, a: [2]f32) -> Rect {
    return {r.min - a, r.max + a}
}

@(require_results) rect_scale :: proc(r: Rect, a: [2]f32) -> Rect {
    size := rect_full_size(r) * 0.5
    center := rect_center(r)
    return {center - size * a, center + size * a}
}

@(require_results) rect_contains_point :: proc(r: Rect, p: [2]f32) -> bool {
    return p.x > r.min.x && p.y > r.min.y && p.x < r.max.x && p.y < r.max.y
}

@(require_results) rect_clamp_point :: proc(r: Rect, p: [2]f32) -> [2]f32 {
    return {clamp(p.x, r.min.x, r.max.x), clamp(p.y, r.min.y, r.max.y)}
}

@(require_results) rect_cut_left :: proc(r: ^Rect, a: f32) -> Rect {
    minx := r.min.x
    r.min.x = min(r.max.x, r.min.x + a)
    return {{minx, r.min.y}, {r.min.x, r.max.y}}
}

@(require_results) rect_cut_right :: proc(r: ^Rect, a: f32) -> Rect {
    maxx := r.max.x
    r.max.x = max(r.min.x, r.max.x - a)
    return {{r.max.x, r.min.y}, {maxx, r.max.y}}
}

@(require_results) rect_cut_top :: proc(r: ^Rect, a: f32) -> Rect {
    miny := r.min.y
    r.min.y = min(r.max.y, r.min.y + a)
    return {{r.min.x, miny}, {r.max.x, r.min.y}}
}

@(require_results) rect_cut_bottom :: proc(r: ^Rect, a: f32) -> Rect {
    maxy := r.max.y
    r.max.y = max(r.min.y, r.max.y - a)
    return {{r.min.x, r.max.y}, {r.max.x, maxy}}
}

@(require_results) rect_split_left :: proc(r: ^Rect, t: f32) -> Rect {
    return rect_cut_left(r, (r.max.x - r.min.x) * t)
}

@(require_results) rect_split_right :: proc(r: ^Rect, t: f32) -> Rect {
    return rect_cut_right(r, (r.max.x - r.min.x) * t)
}

@(require_results) rect_split_top :: proc(r: ^Rect, t: f32) -> Rect {
    return rect_cut_top(r, (r.max.y - r.min.y) * t)
}

@(require_results) rect_split_bottom :: proc(r: ^Rect, t: f32) -> Rect {
    return rect_cut_bottom(r, (r.max.y - r.min.y) * t)
}



/////////////////////////////////////////////////////////////////////////////////////////
// MARK: Affine Transform
//

Transform :: struct {
    pos:    [3]f32,
    mat:    matrix[3, 3]f32,
}

TRANSFORM_IDENTITY :: Transform{
    pos = 0,
    mat = 1,
}

@(require_results)
transform_make :: proc "contextless" (
    pos:    [3]f32 = 0,
    scale:  [3]f32 = 1,
    rot:    quaternion128 = 1,
) -> Transform {
    return {
        pos = pos,
        mat = linalg.matrix3_from_quaternion_f32(rot) * linalg.matrix3_scale_f32(scale),
    }
}

transform_make_angle_axis :: proc "contextless" (
    pos:    [3]f32 = 0,
    scale:  [3]f32 = 1,
    angle:  f32 = 0,
    axis:   [3]f32 = {0, 1, 0},
) -> Transform {
    return {
        pos = pos,
        mat = linalg.matrix3_rotate_f32(angle, axis),
    }
}

@(require_results)
transform_point :: proc "contextless" (tran: Transform, point: [3]f32) -> [3]f32 {
    return tran.pos + tran.mat * point
}

@(require_results)
transform_mul :: proc "contextless" (parent, child: Transform) -> Transform {
    return {
        pos = transform_point(parent, child.pos),
        mat = parent.mat * child.mat,
    }
}

@(require_results)
transform_inv :: proc "contextless" (tran: Transform) -> Transform {
    // M = R * S
    // inv(M) = inv(R * S) = inv(S) * inv(R) = R^T / S
    inv_scale := [3]f32{
        1.0 / max(1e-9, linalg.length2(tran.mat[0])),
        1.0 / max(1e-9, linalg.length2(tran.mat[1])),
        1.0 / max(1e-9, linalg.length2(tran.mat[2])),
    }
    inv_rot := intrinsics.transpose(tran.mat)
    inv_rot[0] *= inv_scale[0]
    inv_rot[1] *= inv_scale[1]
    inv_rot[2] *= inv_scale[2]
    return {
        pos = inv_rot * -tran.pos,
        mat = inv_rot,
    }
}



////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Camera
//

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
