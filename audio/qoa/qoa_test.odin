#+test
package qoa

import "base:runtime"
import "core:testing"
import "core:math/rand"
import "core:math"

@(test)
_test_fuzz_encode_decode :: proc(t: ^testing.T) {
    for i in 0..<16 {
        defer free_all(context.temp_allocator)

        num_channels := u32(rand.choice([]int{1, 2}))
        sample_rate := u32(rand.choice([]int{22050, 44100, 48000}))

        total_samples := rand.int_max(100_000) + 100

        src := make([]i16, total_samples * int(num_channels), context.temp_allocator)

        f1 := rand.float64_range(50.0, 1000.0)
        f2 := rand.float64_range(1000.0, 5000.0)
        for s in 0..<total_samples {
            t_sec := f64(s) / f64(sample_rate)

            wave := math.sin(2.0 * math.PI * f1 * t_sec) * 15000.0
            wave += math.sin(2.0 * math.PI * f2 * t_sec) * 8000.0

            for c in 0..<int(num_channels) {
                noise := rand.float64_range(-20.0, 20.0)
                sample_f64 := wave + noise
                src[s * int(num_channels) + c] = i16(clamp(sample_f64, -32768.0, 32767.0))
            }
        }

        enc_desc := Desc{
            sample_rate = sample_rate,
            num_channels = num_channels,
        }

        enc, enc_ok := encode(&enc_desc, src, context.temp_allocator)
        testing.expectf(t, enc_ok, "Iter %d: Failed to encode", i)

        dec_desc, dec_samples, dec_ok := decode(enc, context.temp_allocator)
        testing.expectf(t, dec_ok, "Iter %d: Failed to decode", i)

        testing.expectf(t, dec_desc.samples == u32(total_samples), "Iter %d: Sample count mismatch. Got %d, want %d", i, dec_desc.samples, total_samples)
        testing.expectf(t, dec_desc.num_channels == num_channels, "Iter %d: Channel mismatch. Got %d, want %d", i, dec_desc.num_channels, num_channels)
        testing.expectf(t, dec_desc.sample_rate == sample_rate, "Iter %d: Sample rate mismatch. Got %d, want %d", i, dec_desc.sample_rate, sample_rate)
        testing.expectf(t, len(dec_samples) == len(src), "Iter %d: Buffer length mismatch.", i)

        MAX_ERROR :: 1500
        sum_diff: i64 = 0
        for s, idx in dec_samples {
            diff := abs(i32(s) - i32(src[idx]))
            sum_diff += i64(diff)
        }
        avg_diff := f64(sum_diff) / f64(len(src))

        testing.expectf(t, avg_diff < MAX_ERROR, "Iter %d: Average error too high (%f). Length: %d, Channels: %d", i, avg_diff, total_samples, num_channels)
    }
}
