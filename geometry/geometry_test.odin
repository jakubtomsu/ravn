#+test
#+private file
#+vet unused shadowing explicit-allocators style
package ravn_geometry

import "core:testing"
import "core:math/linalg"
import "core:math/rand"


@(test)
_test_sweep_point_vs_plane :: proc(t: ^testing.T) {
    norm := [3]f32{0, 1, 0}
    dist := f32(0.0)
    _expect_hit(t, 0.5, sweep_point_vs_plane({0, 5, 0}, {0, -10, 0}, norm, dist))
    _expect_hit(t, 5.0, sweep_point_vs_plane({0, 5, 0}, {0, -1, 0}, norm, dist, 10)) // Equivalent move/range scaling
    _expect_miss(t, sweep_point_vs_plane({0, 5, 0}, {1, 0, 0}, norm, dist))    // Miss: Parallel ray
    _expect_miss(t, sweep_point_vs_plane({0, 5, 0}, {0, 10, 0}, norm, dist))   // Miss: Pointing away
    _expect_miss(t, sweep_point_vs_plane({0, 5, 0}, {0, -1, 0}, norm, dist, 2)) // Miss: Exhausted range
}

@(test)
_test_sweep_point_vs_sphere :: proc(t: ^testing.T) {
    center := [3]f32{0, 0, 0}
    rad := f32(2.0)
    _expect_hit(t, 0.3, sweep_point_vs_sphere({0, 5, 0}, {0, -10, 0}, center, rad))
    _expect_hit(t, 0.5, sweep_point_vs_sphere({2, 5, 0}, {0, -10, 0}, center, rad)) // Grazing tangent hit
    _expect_hit(t, 0.0, sweep_point_vs_sphere({0, 1, 0}, {0, 10, 0}, center, rad))  // Hit: Starts inside
    _expect_miss(t, sweep_point_vs_sphere({3, 5, 0}, {0, -10, 0}, center, rad))     // Miss: Passes by entirely
    _expect_miss(t, sweep_point_vs_sphere({0, 5, 0}, {0, -1, 0}, center, rad, 2.9)) // Miss: Exhausted range
}

@(test)
_test_sweep_point_vs_aabb :: proc(t: ^testing.T) {
    bmin, bmax := [3]f32{-1, -1, -1}, [3]f32{1, 1, 1}
    _expect_hit(t, 0.4, sweep_point_vs_aabb({0, 5, 0}, {0, -10, 0}, bmin, bmax)) // Face hit
    _expect_hit(t, 0.5, sweep_point_vs_aabb({2, 2, 2}, {-2, -2, -2}, bmin, bmax)) // Corner/Diagonal hit
    _expect_hit(t, 0.0, sweep_point_vs_aabb({0, 0, 0}, {10, 0, 0}, bmin, bmax))  // Hit: Starts inside
    _expect_miss(t, sweep_point_vs_aabb({2, 5, 0}, {0, -10, 0}, bmin, bmax))     // Miss: Parallel bypass
    _expect_miss(t, sweep_point_vs_aabb({0, 5, 0}, {0, -1, 0}, bmin, bmax, 3.0)) // Miss: Exhausted range
}

@(test)
_test_sweep_point_vs_triangle :: proc(t: ^testing.T) {
    tri := [3][3]f32{{-1, 0, -1}, {1, 0, -1}, {0, 0, 1}}
    _expect_hit(t, 0.5, sweep_point_vs_triangle({0, 5, 0}, {0, -10, 0}, tri)) // Center hit
    _expect_hit(t, 0.5, sweep_point_vs_triangle({0, -5, 0}, {0, 10, 0}, tri)) // Backface hit (no culling)
    _expect_miss(t, sweep_point_vs_triangle({0, 0.5, 0}, {10, 0, 0}, tri)) // Miss: Parallel ray
    _expect_miss(t, sweep_point_vs_triangle({2, 5, 0}, {0, -10, 0}, tri))  // Miss: Barycentric outer bounds
}

@(test)
_test_sweep_point_vs_cylinder :: proc(t: ^testing.T) {
    pts := [2][3]f32{{0, -2, 0}, {0, 2, 0}}
    rad := f32(1.0)
    _expect_hit(t, 0.4, sweep_point_vs_cylinder({5, 0, 0}, {-10, 0, 0}, pts, rad)) // Barrel hit
    _expect_hit(t, 0.3, sweep_point_vs_cylinder({0, 5, 0}, {0, -10, 0}, pts, rad)) // Endcap hit
    _expect_hit(t, 0.0, sweep_point_vs_cylinder({0, 0, 0}, {10, 0, 0}, pts, rad))  // Starts inside
    _expect_miss(t, sweep_point_vs_cylinder({2, 5, 0}, {0, -10, 0}, pts, rad))     // Parallel miss
}

@(test)
_test_sweep_point_vs_capsule :: proc(t: ^testing.T) {
    pts := [2][3]f32{{0, -2, 0}, {0, 2, 0}}
    rad := f32(1.0)
    _expect_hit(t, 0.2, sweep_point_vs_capsule({0, 5, 0}, {0, -10, 0}, pts, rad))  // Top cap hit: (5 - 3)/10 = 0.2
    _expect_hit(t, 0.0, sweep_point_vs_capsule({0, 0, 0}, {0, 10, 0}, pts, rad))   // Starts inside
}


@(test)
_test_sweep_sphere_vs_aabb :: proc(t: ^testing.T) {
    bmin, bmax := [3]f32{-1, -1, -1}, [3]f32{1, 1, 1}
    rad := f32(1.0)
    _expect_hit(t, 0.3, sweep_sphere_vs_aabb({0, 5, 0}, {0, -10, 0}, rad, bmin, bmax))
    _expect_hit(t, 0.366666, sweep_sphere_vs_aabb({5, 1.666666, 1.666666}, {-10, 0, 0}, 1.0, bmin, bmax))
    _expect_hit(t, 0.0, sweep_sphere_vs_aabb({0, 1, 0}, {0, 10, 0}, rad, bmin, bmax)) // Hit: Starts inside
    _expect_miss(t, sweep_sphere_vs_aabb({5, 2, 0}, {-10, 0, 0}, rad, bmin, bmax)) // Parallel
    _expect_miss(t, sweep_sphere_vs_aabb({5, 5, 5}, {0, -10, 0}, rad, bmin, bmax)) // Miss entirely
}

@(test)
_test_sweep_sphere_vs_triangle :: proc(t: ^testing.T) {
    tri := [3][3]f32{{-1, 0, -1}, {1, 0, -1}, {0, 0, 1}}
    rad := f32(1.0)
    _expect_hit(t, 0.4, sweep_sphere_vs_triangle({0, 5, 0}, {0, -10, 0}, rad, tri))
    _expect_hit(t, 0.5, sweep_sphere_vs_triangle({0, 5, 2}, {0, -10, 0}, rad, tri))
    _expect_miss(t, sweep_sphere_vs_triangle({0, 5, 3}, {0, -10, 0}, rad, tri)) // Miss: Passes cleanly
    _expect_hit(t, 0.0, sweep_sphere_vs_triangle({0, 0.5, 0}, {0, 10, 0}, rad, tri)) // Hit: Starts inside
    // FIXME
    // _expect_miss(t, sweep_sphere_vs_triangle({0, 5, -2}, {0, -10, 0}, rad, tri)) // Parallel
}


// MARK: Fuzz

@(test)
_test_fuzz_sphere :: proc(t: ^testing.T) {
    Sphere :: struct { center: [3]f32, rad: f32 }
    _fuzz_sweep(t, "sphere",
        proc() -> Sphere { return {_rand_vec3(-2, 2), rand.float32_range(0.25, 2.5)} },
        proc(p: [3]f32, s: Sphere) -> f32 { return get_sphere_dist(p, s.center, s.rad) },
        proc(pos, move: [3]f32, s: Sphere, r: f32) -> (f32, bool) { return sweep_point_vs_sphere(pos, move, s.center, s.rad, r) },
    )
}

@(test)
_test_fuzz_aabb :: proc(t: ^testing.T) {
    Box :: struct { center, ext: [3]f32 }
    _fuzz_sweep(t, "aabb",
        proc() -> Box { return {_rand_vec3(-2, 2), _rand_vec3(0.25, 2.5)} },
        proc(p: [3]f32, s: Box) -> f32 { return get_box_dist(p, s.center, s.ext) },
        proc(pos, move: [3]f32, s: Box, r: f32) -> (f32, bool) { return sweep_point_vs_aabb(pos, move, s.center - s.ext, s.center + s.ext, r) },
    )
}

@(test)
_test_fuzz_sphere_vs_aabb :: proc(t: ^testing.T) {
    Swept_Box :: struct { center, ext: [3]f32, rad: f32 }
    _fuzz_sweep(t, "sphere_vs_aabb",
        proc() -> Swept_Box { return {_rand_vec3(-2, 2), _rand_vec3(0.25, 2.0), rand.float32_range(0.1, 1.5)} },
        proc(p: [3]f32, s: Swept_Box) -> f32 { return get_box_dist(p, s.center, s.ext) - s.rad },
        proc(pos, move: [3]f32, s: Swept_Box, r: f32) -> (f32, bool) { return sweep_sphere_vs_aabb(pos, move, s.rad, s.center - s.ext, s.center + s.ext, r) },
    )
}

@(test)
_test_fuzz_triangle :: proc(t: ^testing.T) {
    _fuzz_sweep(t, "triangle",
        _rand_triangle,
        proc(p: [3]f32, tri: [3][3]f32) -> f32 { return get_triangle_dist(p, tri) },
        proc(pos, move: [3]f32, tri: [3][3]f32, r: f32) -> (f32, bool) { return sweep_point_vs_triangle(pos, move, tri, r) },
        is_solid = false,
    )
}

@(test)
_test_fuzz_sphere_vs_triangle :: proc(t: ^testing.T) {
    Swept_Tri :: struct { tri: [3][3]f32, rad: f32 }
    _fuzz_sweep(t, "sphere_vs_triangle",
        proc() -> Swept_Tri { return {_rand_triangle(), rand.float32_range(0.1, 1.5)} },
        proc(p: [3]f32, s: Swept_Tri) -> f32 { return get_triangle_dist(p, s.tri) - s.rad },
        proc(pos, move: [3]f32, s: Swept_Tri, r: f32) -> (f32, bool) { return sweep_sphere_vs_triangle(pos, move, s.rad, s.tri, r) },
    )
}

@(test)
_test_fuzz_capsule :: proc(t: ^testing.T) {
    Capsule :: struct { pts: [2][3]f32, rad: f32 }
    _fuzz_sweep(t, "capsule",
        proc() -> Capsule { return {_rand_segment(0.2, 3.0), rand.float32_range(0.2, 2.0)} },
        proc(p: [3]f32, s: Capsule) -> f32 { return get_line_dist(p, s.pts) - s.rad },
        proc(pos, move: [3]f32, s: Capsule, r: f32) -> (f32, bool) { return sweep_point_vs_capsule(pos, move, s.pts, s.rad, r) },
    )
}

@(test)
_test_fuzz_cylinder :: proc(t: ^testing.T) {
    Cylinder :: struct { pts: [2][3]f32, rad: f32 }
    _fuzz_sweep(t, "cylinder",
        proc() -> Cylinder { return {_rand_segment(0.3, 3.0), rand.float32_range(0.2, 2.0)} },
        proc(p: [3]f32, s: Cylinder) -> f32 { return get_cylinder_dist(p, s.pts, s.rad) },
        proc(pos, move: [3]f32, s: Cylinder, r: f32) -> (f32, bool) { return sweep_point_vs_cylinder(pos, move, s.pts, s.rad, r) },
    )
}

_fuzz_sweep :: proc(
    t: ^testing.T,
    name: string,
    make_shape: proc() -> $Shape,
    sdf: proc(p: [3]f32, s: Shape) -> f32,
    sweep: proc(pos, move: [3]f32, s: Shape, range: f32) -> (f32, bool),
    is_solid := true,
    loc := #caller_location,
) {
    FUZZ_ITERS  :: 4096
    INSIDE_EPS  :: 2e-3
    GRAZE_EPS   :: 3e-3
    SURF_EPS    :: 3e-3
    HIT_EPS     :: 1e-4
    MARCH_STEPS :: 128
    
    rng := rand.create(t.seed)
    context.random_generator = rand.default_random_generator(&rng)

    for i in 0..<FUZZ_ITERS {
        shape := make_shape()
        pos := _rand_vec3(-4, 4)
        move := linalg.normalize(-pos + _rand_vec3(-2, 2)) * rand.float32_range(2, 8)
        sweep_range := rand.float32_range(0.25, 2.5)

        speed := linalg.length(move)
        dir := move / speed
        max_dist := speed * sweep_range

        hit_t, ok := sweep(pos, move, shape, sweep_range)
        sd0 := sdf(pos, shape)

        if is_solid && sd0 < -INSIDE_EPS {
            testing.expectf(t, ok && abs(hit_t) <= 1e-4, "[%s sweep iter %d] started inside (sd=%v): expected ok=true, t=0; got ok=%v, t=%v", name, i, sd0, ok, hit_t, loc = loc)
            continue
        }

        if ok {
            testing.expectf(t, hit_t >= -1e-5 && hit_t <= sweep_range + 1e-5, "[%s sweep iter %d] t=%v out of [0, %v]", name, i, hit_t, sweep_range, loc = loc)
            sd_hit := sdf(pos + move * hit_t, shape)
            testing.expectf(t, abs(sd_hit) <= SURF_EPS, "[%s sweep iter %d] hit off surface: sd=%v, t=%v", name, i, sd_hit, hit_t, loc = loc)
        }

        march_limit := ok ? (hit_t * speed - GRAZE_EPS) : max_dist
        if sd0 <= GRAZE_EPS || march_limit <= 0 {
            continue
        }

        tau: f32 = 0
        for _ in 0..<MARCH_STEPS {
            d := sdf(pos + dir * tau, shape)
            if d < -GRAZE_EPS {
                reason := ok ? "skipped earlier entry" : "missed hit"
                testing.expectf(t, false, "[%s sweep iter %d] %s at dist=%v/%v (sd=%v)", name, i, reason, tau, march_limit, d, loc = loc)
                break
            }
            tau += d <= HIT_EPS ? GRAZE_EPS : d
            if tau > march_limit {
                break
            }
        }
    }
}



// MARK: Util

_rand_vec3 :: proc(low, high: f32) -> [3]f32 {
    return {rand.float32_range(low, high), rand.float32_range(low, high), rand.float32_range(low, high)}
}

_rand_dir :: proc() -> [3]f32 {
    for {
        v := _rand_vec3(-1, 1)
        if linalg.length2(v) > 1e-4 {
            return linalg.normalize(v)
        }
    }
}

_rand_triangle :: proc() -> [3][3]f32 {
    for {
        tri := [3][3]f32{_rand_vec3(-2.5, 2.5), _rand_vec3(-2.5, 2.5), _rand_vec3(-2.5, 2.5)}
        if linalg.length2(linalg.cross(tri[1] - tri[0], tri[2] - tri[0])) > 0.05 {
            return tri
        }
    }
}

_rand_segment :: proc(min_len, max_len: f32) -> [2][3]f32 {
    a := _rand_vec3(-2, 2)
    return {a, a + _rand_dir() * rand.float32_range(min_len, max_len)}
}

_expect_hit :: proc(t: ^testing.T, expected_t: f32, actual_t: f32, actual_ok: bool, loc := #caller_location) {
    testing.expectf(t, actual_ok, "Expected a hit, got a miss. Returned t=%v", actual_t, loc=loc)
    if actual_ok {
        diff := abs(actual_t - expected_t)
        testing.expectf(t, diff < 1e-4, "Expected t=%v, got %v", expected_t, actual_t, loc=loc)
    }
}

_expect_miss :: proc(t: ^testing.T, actual_t: f32, actual_ok: bool, loc := #caller_location) {
    testing.expectf(t, !actual_ok, "Expected a miss, got a hit with t=%v", actual_t, loc=loc)
}
