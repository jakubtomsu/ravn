#+test
#+vet shadowing unused
package ravn

import "core:math/linalg"
import "core:log"
import "core:testing"

@(test)
_strip_path_name_test :: proc(t: ^testing.T) {
    testing.expect(t, strip_path_name("bar.txt") == "bar")
    testing.expect(t, strip_path_name("foo/bar.txt") == "bar")
    testing.expect(t, strip_path_name("foo\\bar.txt") == "bar")
    testing.expect(t, strip_path_name("foo/foo2/bar.txt.bin") == "bar")
}

@(test)
_normalize_path_test :: proc(t: ^testing.T) {
    testing.expect(t, normalize_path("foo") == "foo")
    testing.expect(t, normalize_path("Foo") == "foo")
    testing.expect(t, normalize_path("Hello\\World") == "hello/world")
    testing.expect(t, normalize_path("_123_!@+你好!") == "_123_!@+你好!")
}

@(test)
_uv_packing :: proc(t: ^testing.T) {
    for x in -8..=8 {
        for y in -8..=8 {
            p := [2]f32{f32(x), f32(y)}
            packed := pack_uv_unorm16(p)
            unpacked := unpack_uv_unorm16(packed)
            if !testing.expect(t, linalg.distance(p, unpacked) < 0.001) {
                log.info(p, packed, unpacked)
            }
        }
    }
}


@(test)
_signed_color_packing :: proc(t: ^testing.T) {
    for x in -2..=2 {
        for y in -2..=2 {
            for z in -2..=2 {
                for w in -2..=2 {
                    p := [4]f32{f32(x), f32(y), f32(z), f32(w)}
                    packed := pack_signed_color_unorm8(p)
                    unpacked := unpack_signed_color_unorm8(packed)
                    if !testing.expect(t, linalg.distance(p, unpacked) < 0.05) {
                        log.info(p, packed, unpacked)
                    }
                }
            }
        }
    }
}
