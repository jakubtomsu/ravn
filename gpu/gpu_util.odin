#+vet explicit-allocators shadowing style
package ravn_gpu

import "../base"
import "base:runtime"

ptr_bytes :: proc(ptr: ^$T, len := 1) -> []byte {
    return transmute([]byte)runtime.Raw_Slice{ptr, len * size_of(T)}
}

slice_bytes :: proc(s: []$T) -> []byte where T != byte {
    return ([^]byte)(raw_data(s))[:len(s) * size_of(T)]
}

// Cache bucket for lightweight resources.
// Linear SOA search.
Bucket :: struct($Num: int, $Key: typeid, $Val: typeid) {
    len:    i32,
    keys:   [Num]Key,
    vals:   [Num]Val,
}

bucket_find_or_create :: proc(
    bucket:         ^$T/Bucket($N, $K, $V),
    key:            K,
    create_proc:    proc(K) -> V,
) -> (result: V) {
    for i in 0..<bucket.len {
        if key == bucket.keys[i] {
            return bucket.vals[i]
        }
    }

    index := bucket.len
    if index >= len(bucket.keys) {
        base.log_err("%v Cache Bucket is full", type_info_of(V))
        return {}
    }

    // log.infof("{} Cache Miss", type_info_of(V))

    result = create_proc(key)

    bucket.keys[index] = key
    bucket.vals = result
    bucket.len += 1

    return result
}

clone_to_cstring :: proc(s: string, allocator := context.allocator, loc := #caller_location) -> (res: cstring, err: runtime.Allocator_Error) #optional_allocator_error {
    c := make([]byte, len(s)+1, allocator, loc) or_return
    copy(c, s)
    c[len(s)] = 0
    return cstring(&c[0]), nil
}
