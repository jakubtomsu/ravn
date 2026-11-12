package ravn_base

import "base:runtime"

RELEASE :: #config(RELEASE, false)

Handle_Gen :: u8
Handle_Index :: u16

Handle :: struct {
    index:  Handle_Index,
    gen:    Handle_Gen,
    _:      u8,
}

#assert(size_of(Handle) == 4)

// Quickly checks if x is not NaN or Inf
@(require_results)
is_finite_f32 :: #force_inline proc(x: f32) -> bool {
    return ((transmute(u32)x) & 0x7F800000) != 0x7F800000
}

@(require_results)
is_finite_vec :: #force_inline proc(v: [$N]f32) -> bool {
    res := true
    for x in v {
        res &= is_finite_f32(x)
    }
    return res
}

@(require_results)
hash_fnv64a :: proc "contextless" (data: []byte, seed: u64) -> u64 {
    h: u64 = seed
    for b in data {
        h = (h ~ u64(b)) * 0x100000001b3
    }
    return h
}

// https://nullprogram.com/blog/2018/07/31/

@(require_results)
hash_murmurhash32_mix32 :: proc "contextless" (x: u32) -> u32 {
    x := x
    x ~= x >> 16
    x *= 0x85ebca6b
    x ~= x >> 13
    x *= 0xc2b2ae35
    x ~= x >> 16
    return x
}

@(require_results)
hash_splittable64 :: proc "contextless" (x: u64) -> u64 {
    x := x
    x ~= x >> 30
    x *= 0xbf58476d1ce4e5b9
    x ~= x >> 27
    x *= 0x94d049bb133111eb
    x ~= x >> 31
    return x
}
