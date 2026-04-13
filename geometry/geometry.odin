package raven_collision

import "core:math/linalg"
import "base:intrinsics"

// MARK: Point sweeps

@(require_results)
sweep_point_vs_plane :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    normal: [3]f32,
    dist:   f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #optional_ok {
    denom := linalg.dot(normal, move)
    t = (dist - linalg.dot(normal, pos)) * (1.0 / denom)
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
) -> (t: f32, ok: bool) #optional_ok {
    m := pos - center
    b := linalg.dot(m, move)
    c := linalg.length2(m) - rad * rad
    move_len2 := linalg.length2(move)
    discr := b * b - c * move_len2
    if (c > 0 && b > 0) || move_len2 == 0 || discr < 0 {
        return range, false
    }
    
    t = -b - intrinsics.sqrt(discr)
    t = max(0, t) / move_len2
    ok = t * t <= range
    
    return ok ? t : range, ok
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
) -> (t: f32, ok: bool) #optional_ok {
    inv_move := 1.0 / move

    t1 := (aabb_min - pos) * inv_move
    t2 := (aabb_max - pos) * inv_move

    tmin := max(min(t1.x, t2.x), min(t1.y, t2.y), min(t1.z, t2.z))
    tmax := min(max(t1.x, t2.x), max(t1.y, t2.y), max(t1.z, t2.z))

    ok = tmax >= max(0.0, tmin) && tmin < range

    return ok ? tmin : range, ok
}

@(require_results)
sweep_point_vs_triangle :: proc "contextless" (
    pos:        [3]f32,
    move:       [3]f32,
    points:     [3][3]f32,
    range:      f32 = 1,
) -> (t: f32, ok: bool) #optional_ok {
    ab := points[1] - points[0]
    ac := points[2] - points[0]

    normal := linalg.cross(ab, ac)
    denom := linalg.dot(move, normal)
    
    rel_pos := points[0] - pos
    t = linalg.dot(rel_pos, normal) * (1.0 / denom)
    
    tangent := linalg.cross(move, rel_pos)
    uv := [2]f32{
        -linalg.dot(ac, tangent),
        linalg.dot(ab, tangent),
    }
    
    if denom < 0 {
        uv = -uv
    }
    
    ok = t >= 0 && t <= range &&
        abs(denom) > 1e-10 &&
        uv.x >= 0 && uv.y >= 0 && uv.x + uv.y <= abs(denom)
    
    return ok ? t : range, ok
}

@(require_results)
sweep_point_vs_capsule :: proc "contextless" (
    pos:    [3]f32,
    move:   [3]f32,
    points: [2][3]f32,
    rad:    f32,
    range:  f32 = 1,
) -> (t: f32, ok: bool) #optional_ok {
    d := points[1] - points[0]
    m := pos - points[0]
    md := linalg.dot(m, d)
    nd := linalg.dot(move, d)
    dd := linalg.dot(d, d)
    // Test if segment fully outside either endcap of cylinder
    if md + rad < 0 && md + nd + rad < 0 {
        return 1, false // Segment outside ’a’ side of cylinder
    }
    if md - rad > dd && md + nd - rad > dd {
        return 1, false // Segment outside ’b’ side of cylinder
    }
    nn := linalg.dot(move, move)
    mn := linalg.dot(m, move)
    mm := linalg.dot(m, m)
    a := dd * nn - nd * nd
    k := mm - rad * rad
    c := dd * k - md * md
    EPS :: 1e-6
    if abs(a) < EPS {
        // Segment runs parallel to cylinder axis
        if c > 0 {
            return 1, false
        }
        // Now known that segment intersects cylinder; figure out how it intersects
        if md < 0 {
            if (k > 0 && mn > 0) || nn == 0 {
                return 1, false
            }
            discr := mn * mn - k * nn
            // A negative discriminant corresponds to ray missing sphere
            if discr < 0 do return 1, false
            // Ray now found to intersect sphere, compute smallest t value of intersection
            t = -mn - intrinsics.sqrt(discr)
            // If t is negative, ray started inside sphere so clamp t to zero
            t /= nn
            return t, true
        } else if md > dd {
            m := pos - points[1]
            b := linalg.dot(m, move)
            c := linalg.dot(m, m) - rad * rad
            // Exit if r’s origin outside s (c > 0) and r pointing away from s (b > 0)
            if (c > 0 && b > 0) || nn == 0 {
                return 1, false
            }
            discr := b * b - c * nn
            // A negative discriminant corresponds to ray missing sphere
            if discr < 0 do return 1, false
            // Ray now found to intersect sphere, compute smallest t value of intersection
            t = -b - intrinsics.sqrt(discr)
            // If t is negative, ray started inside sphere so clamp t to zero
            t /= nn
            return t, true
        } else {
            // ’a’ lies inside cylinder
            t = 0
        }
        return t, true
    }
    b := dd * mn - nd * md
    discr := b * b - a * c
    if discr < 0 {
        return 1, false // no real roots
    }
    t = (-b - intrinsics.sqrt(discr)) / a
    if t < 0 || t > 1 {
        return 1, false // intersection outside segment
    }
    if md + t * nd < 0 {
        if (k > 0 && mn > 0) || nn == 0 {
            return 1, false
        }
        discr := mn * mn - k * nn
        // A negative discriminant corresponds to ray missing sphere
        if discr < 0 do return 1, false
        t = -mn - intrinsics.sqrt(discr)
        t /= nn
        return t, true
    } else if md + t * nd > dd {
        m := pos - points[1]
        b := linalg.dot(m, move)
        c := linalg.dot(m, m) - rad * rad
        if (c > 0 && b > 0) || nn == 0 {
            return 1, false
        }
        discr := b * b - c * nn
        if discr < 0 do return 1, false
        t = -b - intrinsics.sqrt(discr)
        t /= nn
        return t, true
    }
    return t, true
}


// MARK: Gradients



@(require_results)
dirlen :: proc "contextless" (v: [3]f32) -> (dir: [3]f32, length: f32) {
    length = #force_inline linalg.length(v)
    dir = v / max(0.001, length)
    return dir, length
}
