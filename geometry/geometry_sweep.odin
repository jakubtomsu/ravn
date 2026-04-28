#+vet shadowing
package raven_geometry

import "core:math/linalg"
import "base:intrinsics"
import "core:simd/x86"

LANES :: 8

@(require_results)
sweep_point_vs_plane :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    normal: [3]f32,
    dist:   f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    denom := linalg.vector_dot(normal, move)
    t = (dist - linalg.vector_dot(normal, pos)) * (1.0 / denom)
    ok = t >= 0 && t <= range && abs(denom) > 1e-10
    return ok ? t : range, ok
}

@(require_results)
sweep_point_vs_sphere :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    center: [3]f32,
    rad:    f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    m := pos - center
    b := linalg.vector_dot(m, move)
    c := linalg.vector_length2(m) - rad * rad
    move_len2 := linalg.vector_length2(move)
    discr := b * b - c * move_len2

    if (c > 0 && b > 0) || move_len2 == 0 || discr < 0 {
        return range, false
    }

    t = -b - intrinsics.sqrt(discr)
    t *= 1.0 / move_len2
    ok = t <= range

    return ok ? t : range, ok
}

// NOTE: move vector must have length greater than zero.
@(require_results)
sweep_point_vs_sphere_simd :: proc "contextless" (
    pos:            [3]#simd[LANES]f32,
    move:           [3]#simd[LANES]f32,
    move_len2:      #simd[LANES]f32,
    move_len2_inv:  #simd[LANES]f32,
    center:         [3]#simd[LANES]f32,
    rad:            #simd[LANES]f32,
    range:          #simd[LANES]f32 = 1,
) -> (t: #simd[LANES]f32, ok: #simd[LANES]u32) #no_bounds_check {
    m := pos - center
    b := dot_simd(m, move)
    c := length2_simd(m) - rad * rad
    discr := b * b - c * move_len2

    ok = ~(
        (intrinsics.simd_lanes_gt(c, 0) &
        intrinsics.simd_lanes_gt(b, 0)) |
        intrinsics.simd_lanes_lt(discr, 0))

    t = -b - intrinsics.sqrt(discr)
    t *= move_len2_inv

    ok &= intrinsics.simd_lanes_le(t, range)

    t = intrinsics.simd_select(ok, t, range)

    return t, ok
}

// NOTE: rays running exactly parallel to one of the planes return miss.
// Expand the AABB by a small epsilon to prevent this (between 1e-6 and 1e-5 shoud be good).
@(require_results)
sweep_point_vs_aabb :: proc "contextless" (
    pos:        [3]f32,
    move:       [3]f32,
    aabb_min:   [3]f32,
    aabb_max:   [3]f32,
    range:      f32 = 1,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    inv_move := 1.0 / move

    t1 := (aabb_min - pos) * inv_move
    t2 := (aabb_max - pos) * inv_move

    tmin := max(min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
    tmax := min(max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))

    ok = tmax >= max(0.0, tmin) && tmin < range

    return ok ? tmin : range, ok
}

@(require_results)
sweep_point_vs_aabb_simd :: proc "contextless" (
    pos:        [3]#simd[LANES]f32,
    inv_move:   [3]#simd[LANES]f32,
    aabb_min:   [3]#simd[LANES]f32,
    aabb_max:   [3]#simd[LANES]f32,
    range:      #simd[LANES]f32 = 1,
) -> (t: #simd[LANES]f32, ok: #simd[LANES]u32) #no_bounds_check {
    t1 := (aabb_min - pos) * inv_move
    t2 := (aabb_max - pos) * inv_move

    tmin := intrinsics.simd_max(
        intrinsics.simd_min(t1.x, t2.x),
        intrinsics.simd_max(
            intrinsics.simd_min(t1.y, t2.y),
            intrinsics.simd_min(t1.z, t2.z),
        ),
    )

    tmax := intrinsics.simd_min(
        intrinsics.simd_max(t1.x, t2.x),
        intrinsics.simd_min(
            intrinsics.simd_max(t1.y, t2.y),
            intrinsics.simd_max(t1.z, t2.z),
        ),
    )

    ok =
        intrinsics.simd_lanes_ge(tmax, intrinsics.simd_max(tmin, 0.0)) &
        intrinsics.simd_lanes_lt(tmin, range)

    t = intrinsics.simd_select(ok, tmin, range)

    return t, ok
}

@(require_results)
sweep_point_vs_triangle :: proc "contextless" (
    pos:        [3]f32,
    move:       [3]f32,
    tri:        [3][3]f32,
    range:      f32 = 1,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    ab := tri[1] - tri[0]
    ac := tri[2] - tri[0]

    normal := linalg.vector_cross3(ab, ac)
    denom := linalg.vector_dot(move, normal)

    rel := tri[0] - pos
    t = linalg.vector_dot(rel, normal) * (1.0 / denom)

    tangent := linalg.vector_cross3(move, rel)
    uv := [2]f32{
        -linalg.vector_dot(ac, tangent),
        linalg.vector_dot(ab, tangent),
    }

    if denom < 0 {
        uv = -uv
    }

    ok = t >= 0 && t <= range &&
        abs(denom) > 1e-6 &&
        uv.x >= 0 && uv.y >= 0 && uv.x + uv.y <= abs(denom)

    return ok ? t : range, ok
}

@(require_results)
sweep_point_vs_triangle_simd :: proc "contextless" (
    pos:        [3]#simd[LANES]f32,
    move:       [3]#simd[LANES]f32,
    tri:        [3][3]#simd[LANES]f32,
    range:      #simd[LANES]f32 = 1,
) -> (t: #simd[LANES]f32, ok: #simd[LANES]u32) #no_bounds_check {
    ab := tri[1] - tri[0]
    ac := tri[2] - tri[0]

    normal := cross_simd(ab, ac)
    denom := dot_simd(move, normal)

    rel := tri[0] - pos
    t = dot_simd(rel, normal) * (1.0 / denom)

    tangent := cross_simd(move, rel)
    uv := [2]#simd[LANES]f32{
        -dot_simd(ac, tangent),
        dot_simd(ab, tangent),
    }

    negate := intrinsics.simd_lanes_le(denom, 0)

    uv[0] = intrinsics.simd_select(negate, -uv[0], uv[0])
    uv[1] = intrinsics.simd_select(negate, -uv[1], uv[1])

    ok =
        intrinsics.simd_lanes_ge(t, 0) &
        intrinsics.simd_lanes_le(t, range) &
        intrinsics.simd_lanes_gt(intrinsics.simd_abs(denom), 1e-6) &
        intrinsics.simd_lanes_ge(uv.x, 0) &
        intrinsics.simd_lanes_ge(uv.y, 0) &
        intrinsics.simd_lanes_le(uv.x + uv.y, intrinsics.simd_abs(denom))

    t = intrinsics.simd_select(ok, t, range)

    return t, ok
}

// Triangle expanded by 2*radius along the normal.
// Sweeps a 5 sided polyhedron but only the two triangles are intersected.
@(require_results)
sweep_point_vs_triangle_slab :: proc "contextless" (
    pos:        [3]f32,
    move:       [3]f32,
    tri:        [3][3]f32,
    rad:        f32,
    range:      f32 = 1,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    ab := tri[1] - tri[0]
    ac := tri[2] - tri[0]

    normal := linalg.vector_cross3(ab, ac)
    denom := linalg.vector_dot(move, normal)
    inv_denom := 1.0 / denom

    nrad := linalg.normalize(normal) * rad
    nrad = denom < 0 ? nrad : -nrad

    rel := tri[0] + nrad - pos
    t = linalg.vector_dot(rel, normal) * inv_denom

    tangent := linalg.vector_cross3(move, rel)
    uv := [2]f32{
        -linalg.vector_dot(ac, tangent),
        linalg.vector_dot(ab, tangent),
    }

    if denom < 0 {
        uv = -uv
    }

    ok = t >= 0 && t < range &&
        abs(denom) > 1e-6 &&
        uv.x >= 0 && uv.y >= 0 && uv.x + uv.y <= abs(denom)

    return ok ? t : range, ok
}


@(require_results)
sweep_point_vs_uncapped_cylinder :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    points: [2][3]f32,
    rad:    f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    d  := points[1] - points[0]
    m  := pos - points[0]
    dd := linalg.vector_length2(d)
    nd := linalg.vector_dot(move, d)
    md := linalg.vector_dot(m, d)

    a := dd * linalg.vector_length2(move) - nd * nd
    b := dd * linalg.vector_dot(m, move) - nd * md
    c := dd * (linalg.vector_length2(m) - rad * rad) - md * md

    if abs(a) < 1e-6 {
        return range, false
    }

    discr := b * b - a * c
    if discr < 0 {
        return range, false
    }

    t = (-b - intrinsics.sqrt(discr)) / a

    curr_md := md + t * nd
    ok = t >= 0 && t <= range && curr_md >= 0 && curr_md <= dd

    return ok ? t : range, ok
}

@(require_results)
sweep_point_vs_uncapped_cylinder_simd :: proc "contextless" (
    pos:    [3]#simd[LANES]f32,
    move:   [3]#simd[LANES]f32,
    points: [2][3]#simd[LANES]f32,
    rad:    #simd[LANES]f32,
    range:  #simd[LANES]f32 = 1,
) -> (t: #simd[LANES]f32, ok: #simd[LANES]u32) #no_bounds_check {
    d  := points[1] - points[0]
    m  := pos - points[0]
    dd := length2_simd(d)
    nd := dot_simd(move, d)
    md := dot_simd(m, d)

    a := dd * length2_simd(move) - nd * nd
    b := dd * dot_simd(m, move) - nd * md
    c := dd * (length2_simd(m) - rad * rad) - md * md

    discr := b * b - a * c

    t = (-b - intrinsics.sqrt(discr)) / a
    curr_md := md + t * nd

    ok =
        intrinsics.simd_lanes_gt(intrinsics.simd_abs(a), 1e-6) &
        intrinsics.simd_lanes_gt(discr, 0) &
        intrinsics.simd_lanes_ge(t, 0) &
        intrinsics.simd_lanes_le(t, range) &
        intrinsics.simd_lanes_ge(curr_md, 0) &
        intrinsics.simd_lanes_le(curr_md, dd)

    t = intrinsics.simd_select(ok, t, range)

    return t, ok
}


@(require_results)
sweep_point_vs_cylinder :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    points: [2][3]f32,
    rad:    f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    d := points[1] - points[0]
    m := pos - points[0]
    n := move * range
    md := linalg.vector_dot(m, d)
    nd := linalg.vector_dot(n, d)
    dd := linalg.vector_length2(d)

    // Test if segment fully outside either endcap of cylinder
    if (md < 0 && md + nd < 0) || (md > dd && md + nd > dd) {
        return range, false
    }

    nn := linalg.vector_length2(n)
    mn := linalg.vector_dot(m, n)
    k := linalg.vector_length2(m) - rad * rad
    a := dd * nn - nd * nd
    c := dd * k - md * md

    EPS :: 1e-6

    if abs(a) < EPS { // Segment runs parallel to cylinder axis
        if c > 0 {
            return range, false
        }
        if md < 0 {
            t = -mn / nn
        } else if md > dd {
            t = (nd - mn) / nn
        } else {
            t = 0 // starts inside cylinder
        }
        return t, true
    }

    b := dd * mn - nd * md
    discr := b * b - a * c
    if discr < 0 {
        return range, false // no real roots
    }

    t = (-b - intrinsics.sqrt(discr)) / a
    if t > 1 || (t < 0 && c > 0) {
        return range, false // intersection outside segment
    }

    t = max(t, 0)

    ok = true

    // Try intersect endcaps
    if md + t * nd < 0 {
        if nd <= 0 {
            return range, false
        }
        t = -md / nd
        ok = k + t * (2 * mn + t * nn) <= 0
    } else if md + t * nd > dd {
        if nd >= 0 {
            return range, false
        }
        t = (dd - md) / nd
        ok = k + dd - 2 * md + t * (2 * (mn - nd) + t * nn) <= 0
    }

    t *= range

    return t, ok
}

// FIXME: broken endcaps
@(require_results)
sweep_point_vs_capsule :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    points: [2][3]f32,
    rad:    f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    d := points[1] - points[0]
    m := pos - points[0]
    n := move * range
    md := linalg.vector_dot(m, d)
    nd := linalg.vector_dot(n, d)
    dd := linalg.vector_length2(d)


    // Test if segment fully outside either endcap of cylinder
    if (md + rad < 0 && md + nd + rad < 0) || (md - rad > dd && md + nd - rad > dd) {
        return range, false
    }

    nn := linalg.vector_length2(n)
    mn := linalg.vector_dot(m, n)
    mm := linalg.vector_length2(m)
    a := dd * nn - nd * nd
    k := mm - rad * rad
    c := dd * k - md * md

    EPS :: 1e-6
    if abs(a) < EPS { // Segment runs parallel to cylinder axis
        if c > 0 {
            return range, false
        }
        t = 0
    } else {
        b := dd * mn - nd * md
        discr := b * b - a * c
        if discr < 0 {
            return range, false
        }

        t = (-b - intrinsics.sqrt(discr)) / a
        if (t < 0 && c > 0) || t > 1 {
            return range, false // intersection outside segment
        }

        t = max(t, 0)
    }

    // Try intersect endcaps
    if md + t * nd < 0 {
        discr := mn * mn - k * nn
        if (k > 0 && mn > 0) || nn == 0 || discr < 0 {
            return range, false
        }
        t = -mn - intrinsics.sqrt(discr)
        t /= nn
    } else if md + t * nd > dd {
        m = pos - points[1]
        b := linalg.vector_dot(m, n)
        c = linalg.vector_length2(m) - rad * rad
        discr := b * b - c * nn
        if (c > 0 && b > 0) || nn == 0 || discr < 0 {
            return range, false
        }
        t = -b - intrinsics.sqrt(discr)
        t /= nn
    }

    t *= range

    return t, true
}

// Inspired by:
// https://github.com/blat-blatnik/Snippets/blob/main/capsule_triangle_sweep.glsl

sweep_sphere_vs_triangle :: proc(
    pos:    [3]f32,
    move:   [3]f32,
    rad:    f32,
    tri:    [3][3]f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #optional_ok #no_bounds_check {
    v01 := tri[1] - tri[0]
    v02 := tri[2] - tri[0]

    t = range

    for v in tri {
        t = sweep_point_vs_sphere(pos, move, v, rad, t) or_continue
        ok = true
    }

    for v0, i in tri {
        v1 := tri[(i + 1) % 3]
        t = sweep_point_vs_uncapped_cylinder(pos, move, {v0, v1}, rad, t) or_continue
        ok = true
    }

    tt, tok := sweep_point_vs_triangle_slab(pos, move, tri, rad, t)
    if tok && tt < t {
        t = tt
        ok = true
    }


    return t, ok
}

@(require_results)
dirlen :: proc "contextless" (v: [3]f32) -> (dir: [3]f32, length: f32) {
    length = #force_inline linalg.length(v)
    dir = v / max(1e-6, length)
    return dir, length
}

USE_FMA :: intrinsics.has_target_feature("fma")

@(require_results)
dot_simd :: #force_inline proc "contextless" (a, b: [3]#simd[LANES]f32) -> #simd[LANES]f32 {
    when USE_FMA {
        return intrinsics.fused_mul_add(
            a.x, b.x,
            intrinsics.fused_mul_add(
                a.y, b.y,
                a.z * b.z,
            ),
        )
    } else {
        ab := a * b
        return ab.x + ab.y + ab.z
    }
}

@(require_results)
cross_simd :: #force_inline proc "contextless" (a, b: [3]#simd[LANES]f32) -> [3]#simd[LANES]f32 {
    when USE_FMA {
        sub := -b.yzx*a.zxy
        return {
            intrinsics.fused_mul_add(a.y, b.z, sub.x),
            intrinsics.fused_mul_add(a.z, b.x, sub.y),
            intrinsics.fused_mul_add(a.x, b.y, sub.z),
        }
    } else {
	    return a.yzx*b.zxy - b.yzx*a.zxy
    }
}

@(require_results)
length2_simd :: #force_inline proc "contextless" (a: [3]#simd[LANES]f32) -> #simd[LANES]f32 {
    when USE_FMA {
        return intrinsics.fused_mul_add(
            a.x, a.x,
            intrinsics.fused_mul_add(
                a.y, a.y,
                a.z * a.z,
            ),
        )
    } else {
        aa := a * a
        return aa.x + aa.y + aa.z
    }
}


@(require_results)
approx_rsqrt_simd :: #force_inline proc "contextless" (x: #simd[$N]f32) -> #simd[LANES]f32 {
    when ODIN_ARCH == .amd64 && N == 8 {
        return x86._mm256_rsqrt_ps(x)
    } when ODIN_ARCH == .amd64 && N == 4 {
        return x86._mm_rsqrt_ps(x)
    } else {
        // Slow high-precision fallback
        return 1.0 / intrinsics.sqrt(x)
    }
}

@(require_results)
approx_sqrt :: #force_inline proc "contextless" (x: #simd[LANES]f32) -> #simd[LANES]f32 {
    when intrinsics.has_target_feature("avx") {
        return approx_sqrt_avx(x)
    } else when intrinsics.has_target_feature("sse") {
        return approx_sqrt_sse(x)
    } else {
        return intrinsics.sqrt(x)
    }
}

when ODIN_ARCH == .amd64 {
    @(require_results, enable_target_feature="avx")
    approx_sqrt_avx :: proc "contextless" (x: #simd[LANES]f32) -> #simd[LANES]f32 {
        // sqrt(x) == x^0.5 == x * x^-0.5 == x * 1/sqrt(x)
        when LANES == 8 {
            return x * x86._mm256_rsqrt_ps(x)
        } else {
            #panic("Unimplemented")
        }
    }

    @(require_results, enable_target_feature="sse")
    approx_sqrt_sse :: proc "contextless" (x: #simd[LANES]f32) -> #simd[LANES]f32 {
        when LANES == 4 {
            return x * x86._mm_rsqrt_ps(x)
        } else when LANES == 8 {
            split := transmute([2]#simd[4]f32)x
            comb := transmute(#simd[8]f32)[2]#simd[4]f32{
                x86._mm_rsqrt_ps(split.x),
                x86._mm_rsqrt_ps(split.y),
            }
            return x * comb
        } else {
            #panic("Unimplemented")
        }
    }
}
