#+vet shadowing
package ravn_geometry

import "core:math/linalg"
import "base:intrinsics"

// Swept shape intersection tests.
// Swept point is the same as raycast.
//
// The move+range instead of traditional ray dir allows the procs to work both as ray and line intersection.

LANES :: 8
BRUTE_FORCE :: #config(GEOMETRY_BRUTE_FORCE, false) // For debugging purposes.

// MARK: Point

@(require_results)
sweep_point_vs_plane :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    normal: [3]f32,
    dist:   f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #no_bounds_check {
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
) -> (t: f32, ok: bool) #no_bounds_check {
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
    t = max(t, 0.0)
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
    t = intrinsics.simd_max(t, 0.0)

    ok &= intrinsics.simd_lanes_le(t, range)
    return intrinsics.simd_select(ok, t, range), ok
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
) -> (t: f32, ok: bool) #no_bounds_check {
    inv_move := 1.0 / move

    t1 := (aabb_min - pos) * inv_move
    t2 := (aabb_max - pos) * inv_move

    tmin := max(min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z), 0.0)
    tmax := min(max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))

    ok = tmax >= tmin && tmin <= range
    return ok ? tmin : range, ok
}

// W component is ignored
@(require_results)
sweep_point_vs_aabb_simd_single :: #force_inline proc "contextless" (
    pos:        #simd[4]f32,
    inv_move:   #simd[4]f32,
    aabb_min:   #simd[4]f32,
    aabb_max:   #simd[4]f32,
    range:      f32 = 1,
) -> (t: f32, ok: bool) #no_bounds_check {
    t1 := (aabb_min - pos) * inv_move
    t2 := (aabb_max - pos) * inv_move

    mins := transmute([4]f32)intrinsics.simd_min(t1, t2)
    maxs := transmute([4]f32)intrinsics.simd_max(t1, t2)
    tmin := max(mins.x, mins.y, mins.z, 0.0)
    tmax := min(maxs.x, maxs.y, maxs.z)

    ok = tmax >= tmin && tmin <= range
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

    tmin = intrinsics.simd_max(tmin, 0.0)
    ok = intrinsics.simd_lanes_ge(tmax, tmin) &
        intrinsics.simd_lanes_le(tmin, range)
    return intrinsics.simd_select(ok, tmin, range), ok
}

@(require_results)
sweep_point_vs_triangle :: proc "contextless" (
    pos:        [3]f32,
    move:       [3]f32,
    tri:        [3][3]f32,
    range:      f32 = 1,
) -> (t: f32, ok: bool) #no_bounds_check {
    ab := tri[1] - tri[0]
    ac := tri[2] - tri[0]

    normal := linalg.vector_cross3(ab, ac)
    denom := linalg.vector_dot(move, normal)
    inv_denom := 1.0 / denom

    rel := tri[0] - pos
    t = linalg.vector_dot(rel, normal) * inv_denom

    tangent := linalg.vector_cross3(move, rel)
    uv := [2]f32{
        linalg.vector_dot(ab, tangent),
        -linalg.vector_dot(ac, tangent),
    }

    uv *= inv_denom

    ok = t >= 0 && t <= range &&
        abs(denom) > 1e-6 &&
        uv.x >= 0 && uv.y >= 0 && uv.x + uv.y <= 1.0

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
        dot_simd(ab, tangent),
        -dot_simd(ac, tangent),
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

@(require_results)
sweep_point_vs_uncapped_cylinder :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    points: [2][3]f32,
    rad:    f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #no_bounds_check {
    d  := points[1] - points[0]
    m  := pos - points[0]
    dd := linalg.vector_length2(d)
    nd := linalg.vector_dot(move, d)
    md := linalg.vector_dot(m, d)

    a := dd * linalg.vector_length2(move) - nd * nd
    b := dd * linalg.vector_dot(m, move) - nd * md
    c := dd * (linalg.vector_length2(m) - rad * rad) - md * md

    discr := b * b - a * c
    if a < 1e-6 || discr < 0 {
        return range, false
    }

    sqrt_discr := intrinsics.sqrt(discr)
    inv_a := 1.0 / a

    t0 := (-b - sqrt_discr) * inv_a
    md0 := md + t0 * nd
    if t0 >= 0 && t0 <= range && md0 >= 0 && md0 <= dd {
        return t0, true
    }

    t1 := (-b + sqrt_discr) * inv_a
    md1 := md + t1 * nd
    if t1 >= 0 && t1 <= range && md1 >= 0 && md1 <= dd {
        return t1, true
    }

    return range, false
}

@(require_results)
sweep_point_vs_cylinder :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    points: [2][3]f32,
    rad:    f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #no_bounds_check {
    d  := points[1] - points[0]
    m  := pos - points[0]
    md := linalg.vector_dot(m, d)
    nd := linalg.vector_dot(move, d)
    dd := linalg.vector_length2(d)

    if (md < 0 && md + nd * range < 0) || (md > dd && md + nd * range > dd) {
        return range, false
    }

    nn := linalg.vector_length2(move)
    mn := linalg.vector_dot(m, move)
    k  := linalg.vector_length2(m) - rad * rad
    a  := dd * nn - nd * nd
    c  := dd * k - md * md

    EPS :: 1e-6
    if abs(a) < EPS {
        if c > 0 || nn == 0 {
            return range, false
        }
        if md < 0 {
            t = -mn / nn
        } else if md > dd {
            t = (linalg.vector_dot(d, move) - mn) / nn
        } else {
            t = 0
        }
        ok = t >= 0 && t <= range
        return ok ? t : range, ok
    }

    b := dd * mn - nd * md
    discr := b * b - a * c
    if discr < 0 {
        return range, false
    }

    t = (-b - intrinsics.sqrt(discr)) / a
    if t > range || (t < 0 && c > 0) {
        return range, false
    }

    t = max(t, 0)
    ok = true

    if md + t * nd < 0 {
        if nd <= 0 do return range, false
        t = -md / nd
        ok = t <= range && k + t * (2 * mn + t * nn) <= 0
    } else if md + t * nd > dd {
        if nd >= 0 do return range, false
        t = (dd - md) / nd
        ok = t <= range && k + dd - 2 * md + t * (2 * (mn - linalg.vector_dot(d, move)) + t * nn) <= 0
    }

    return ok ? t : range, ok
}

@(require_results)
sweep_point_vs_capsule :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    points: [2][3]f32,
    rad:    f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #no_bounds_check {
    d  := points[1] - points[0]
    m  := pos - points[0]
    dd := linalg.vector_length2(d)

    if dd < 1e-8 {
        return sweep_point_vs_sphere(pos, move, points[0], rad, range)
    }

    md := linalg.vector_dot(m, d)
    mm := linalg.vector_length2(m)
    r2 := rad * rad
    c  := dd * (mm - r2) - md * md

    // Inside-start check across the 3 Voronoï regions
    if md <= 0 {
        if mm <= r2 do return 0, true
    } else if md >= dd {
        if linalg.vector_length2(pos - points[1]) <= r2 do return 0, true
    } else {
        if c <= 0 do return 0, true
    }

    best_t := range

    nd := linalg.vector_dot(move, d)
    nn := linalg.vector_length2(move)
    mn := linalg.vector_dot(m, move)

    a := dd * nn - nd * nd
    b := dd * mn - nd * md
    discr := b * b - a * c
    if a > 1e-8 && discr >= 0 {
        cyl_t := (-b - intrinsics.sqrt(discr)) / a
        if cyl_t >= 0 && cyl_t <= best_t {
            hit_md := md + cyl_t * nd
            if hit_md >= 0 && hit_md <= dd {
                best_t = cyl_t
                ok = true
            }
        }
    }

    if mn < 0 {
        c0 := mm - r2
        discr0 := mn * mn - nn * c0
        if discr0 >= 0 {
            s0_t := (-mn - intrinsics.sqrt(discr0)) / nn
            if s0_t >= 0 && s0_t <= best_t {
                best_t = s0_t
                ok = true
            }
        }
    }

    m1 := pos - points[1]
    mn1 := linalg.vector_dot(m1, move)
    if mn1 < 0 {
        c1 := linalg.vector_length2(m1) - r2
        discr1 := mn1 * mn1 - nn * c1
        if discr1 >= 0 {
            s1_t := (-mn1 - intrinsics.sqrt(discr1)) / nn
            if s1_t >= 0 && s1_t <= best_t {
                best_t = s1_t
                ok = true
            }
        }
    }

    return ok ? best_t : range, ok
}



// MARK: Sphere

// Inspired by:
// https://github.com/blat-blatnik/Snippets/blob/main/capsule_triangle_sweep.glsl
@(require_results)
sweep_sphere_vs_aabb :: proc "contextless" (
    pos:        [3]f32,
    move:       [3]f32,
    rad:        f32,
    aabb_min:   [3]f32,
    aabb_max:   [3]f32,
    range:      f32 = 1,
) -> (t: f32, ok: bool) #no_bounds_check {
    move := move
    center := (aabb_min + aabb_max) * 0.5
    extent := aabb_max - center
    rpos := pos - center

    if linalg.length2(rpos - linalg.clamp(rpos, -extent, extent)) <= rad * rad {
        return 0, true
    }

    inv_move := 1.0 / move
    t1 := (aabb_min - rad - pos) * inv_move
    t2 := (aabb_max + rad - pos) * inv_move
    tmin := max(min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z), 0.0)
    tmax := min(max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))

    if !(tmax >= tmin && tmin <= range) {
        return range, false
    }

    hit := rpos + move * tmin
    octant := [3]f32{
        hit.x < 0 ? -1 : 1,
        hit.y < 0 ? -1 : 1,
        hit.z < 0 ? -1 : 1,
    }

    hit *= octant
    move *= octant
    rpos *= octant

    face: int =
        (hit.x > extent.x ? 1 << 0 : 0) |
        (hit.y > extent.y ? 1 << 1 : 0) |
        (hit.z > extent.z ? 1 << 2 : 0)

    switch intrinsics.count_ones(face) {
    case 0, 1:
        return tmin, true

    case 2, 3:
        best_t := range
        hit_any := false

        if BRUTE_FORCE {
            for i in 0..<8 {
                c := extent * [3]f32{
                    bool(i & 1) ? 1 : -1,
                    bool(i & 2) ? 1 : -1,
                    bool(i & 4) ? 1 : -1,
                }
                if ct, cok := sweep_point_vs_sphere(rpos, move, c, rad, best_t); cok {
                    best_t = ct
                    hit_any = true
                }
            }
            for axis in 0..<3 {
                u := (axis + 1) % 3
                v := (axis + 2) % 3
                for s0 in 0..<2 {
                    for s1 in 0..<2 {
                        p0, p1: [3]f32
                        p0[axis] = -extent[axis]
                        p1[axis] =  extent[axis]
                        p0[u] = s0 == 0 ? -extent[u] : extent[u]
                        p1[u] = p0[u]
                        p0[v] = s1 == 0 ? -extent[v] : extent[v]
                        p1[v] = p0[v]
                        if et, eok := sweep_point_vs_uncapped_cylinder(rpos, move, {p0, p1}, rad, best_t); eok {
                            best_t = et
                            hit_any = true
                        }
                    }
                }
            }
        } else {
            edges := [3][2][3]f32{
                {extent, {-extent.x,  extent.y,  extent.z}},
                {extent, { extent.x, -extent.y,  extent.z}},
                {extent, { extent.x,  extent.y, -extent.z}},
            }
            for edge in edges {
                if et, eok := sweep_point_vs_uncapped_cylinder(rpos, move, edge, rad, best_t); eok {
                    best_t = et
                    hit_any = true
                }
            }
            if ct, cok := sweep_point_vs_sphere(rpos, move, extent, rad, best_t); cok {
                best_t = ct
                hit_any = true
            }

            // Guard for thin boxes (extent < rad) where a ray reflected into hit >= 0 crosses 0
            if extent.x < rad && move.x < 0 {
                if ct, cok := sweep_point_vs_sphere(rpos, move, {-extent.x, extent.y, extent.z}, rad, best_t); cok {
                    best_t = ct
                    hit_any = true
                }
            }
            if extent.y < rad && move.y < 0 {
                if ct, cok := sweep_point_vs_sphere(rpos, move, {extent.x, -extent.y, extent.z}, rad, best_t); cok {
                    best_t = ct
                    hit_any = true
                }
            }
            if extent.z < rad && move.z < 0 {
                if ct, cok := sweep_point_vs_sphere(rpos, move, {extent.x, extent.y, -extent.z}, rad, best_t); cok {
                    best_t = ct
                    hit_any = true
                }
            }
        }

        return best_t, hit_any
    }

    return range, false
}

@(require_results)
sweep_sphere_vs_triangle :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    rad:    f32,
    tri:    [3][3]f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #no_bounds_check {
    BRUTE_FORCE :: false

    if #force_inline test_sphere_vs_triangle(pos, rad, tri) {
        return 0, true
    }

    ab := tri[1] - tri[0]
    ac := tri[2] - tri[0]
    normal := linalg.vector_cross3(ab, ac)
    normal_len := linalg.length(normal)
    if normal_len <= 1e-6 {
        return range, false
    }

    pa := pos - tri[0]
    dist_n := linalg.vector_dot(pa, normal)
    denom := linalg.vector_dot(move, normal)
    rad_n := rad * normal_len

    t_enter: f32 = 0
    t_exit := range
    slab_valid := true

    if abs(denom) > 1e-6 {
        inv_denom := 1.0 / denom
        signed_rad_n := denom < 0 ? rad_n : -rad_n

        t_plane_enter := (signed_rad_n - dist_n) * inv_denom
        t_plane_exit  := (-signed_rad_n - dist_n) * inv_denom

        t_enter = max(t_plane_enter, 0.0)
        t_exit  = min(t_plane_exit, range)
        slab_valid = t_enter <= t_exit

        if slab_valid && t_plane_enter >= 0 {
            nrad := normal * (signed_rad_n / (normal_len * normal_len))
            rel := nrad - pa
            tangent := linalg.vector_cross3(move, rel)
            u := -linalg.vector_dot(ac, tangent) * inv_denom
            v :=  linalg.vector_dot(ab, tangent) * inv_denom
            if u >= 0 && v >= 0 && u + v <= 1.0 {
                return t_plane_enter, true
            }
        }
    } else {
        slab_valid = abs(dist_n) <= rad_n
    }

    t = range

    if BRUTE_FORCE {
        for v in tri {
            if v_t, v_ok := #force_inline sweep_point_vs_sphere(pos, move, v, rad, t); v_ok {
                t = v_t
                ok = true
            }
        }

        v0 := tri[2]
        for v1 in tri {
            if e_t, e_ok := #force_inline sweep_point_vs_uncapped_cylinder(pos, move, {v0, v1}, rad, t); e_ok {
                t = e_t
                ok = true
            }
            v0 = v1
        }
    } else {
        if !slab_valid {
            return range, false
        }

        p0 := pos + move * t_enter
        p1 := pos + move * t_exit
        t = min(range, t_exit + 1e-5)
        rad_n_sq := rad_n * rad_n

        vert_mask: u8
        v0 := tri[2]
        for v1, i in tri {
            edge := v1 - v0
            out_n := linalg.vector_cross3(edge, normal)
            d0 := linalg.vector_dot(p0 - v0, out_n)
            d1 := linalg.vector_dot(p1 - v0, out_n)
            max_d := max(d0, d1)

            if max_d >= 0 || max_d * max_d <= rad_n_sq * linalg.vector_dot(edge, edge) {
                prev_i := u8((i + 2) % 3)
                vert_mask |= (1 << prev_i) | (1 << u8(i))

                if e_t, e_ok := #force_inline sweep_point_vs_uncapped_cylinder(pos, move, {v0, v1}, rad, t); e_ok {
                    t = e_t
                    ok = true
                }
            }
            v0 = v1
        }

        if vert_mask != 0 {
            for i in 0..<u8(3) {
                if (vert_mask & (1 << i)) != 0 {
                    if v_t, v_ok := #force_inline sweep_point_vs_sphere(pos, move, tri[i], rad, t); v_ok {
                        t = v_t
                        ok = true
                    }
                }
            }
        }
    }

    return ok ? t : range, ok
}



// MARK: Util

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
