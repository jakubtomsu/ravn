#+test
#+private file
#+vet unused shadowing explicit-allocators style
package ravn_geometry

import "core:testing"

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
    _expect_hit_slab(t, 0.4, sweep_point_vs_triangle_slab({0, 5, 0}, {0, -10, 0}, tri, 1.0))
    _expect_miss_slab(t, sweep_point_vs_triangle_slab({0, 5, 0}, {10, 0, 0}, tri, 1.0))
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
_test_sweep_point_vs_uncapped_cylinder :: proc(t: ^testing.T) {
    pts := [2][3]f32{{0, -2, 0}, {0, 2, 0}}
    rad := f32(1.0)
    _expect_hit(t, 0.4, sweep_point_vs_uncapped_cylinder({5, 0, 0}, {-10, 0, 0}, pts, rad)) // Barrel hit
    _expect_miss(t, sweep_point_vs_uncapped_cylinder({0, 5, 0}, {0, -10, 0}, pts, rad))     // Passes thru endcap space
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
    // FIXME
    // _expect_hit(t, 0.0, sweep_sphere_vs_triangle({0, 0.5, 0}, {0, 10, 0}, rad, tri)) // Hit: Starts inside
    // _expect_miss(t, sweep_sphere_vs_triangle({0, 5, -2}, {0, -10, 0}, rad, tri)) // Parallel
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

_expect_hit_slab :: proc(t: ^testing.T, expected_t: f32, actual_t: f32, uv: [2]f32, actual_ok: bool, loc := #caller_location) {
    testing.expectf(t, actual_ok, "Expected a hit, got a miss. Returned t=%v", actual_t, loc=loc)
    if actual_ok {
        diff := abs(actual_t - expected_t)
        testing.expectf(t, diff < 1e-4, "Expected t=%v, got %v (uv: %v)", expected_t, actual_t, uv, loc=loc)
    }
}

_expect_miss_slab :: proc(t: ^testing.T, actual_t: f32, uv: [2]f32, actual_ok: bool, loc := #caller_location) {
    testing.expectf(t, !actual_ok, "Expected a miss, got a hit with t=%v", actual_t, loc=loc)
}
