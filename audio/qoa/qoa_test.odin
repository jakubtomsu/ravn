#+test
package qoa

import "core:mem"
import "base:runtime"
import "core:testing"
import "core:log"
import "core:strings"
import "core:math"
import "../wav"

// Try a different linker if the files bloat compile times too much.
// The samples are from:
// https://qoaformat.org/samples/
// Unzip and put them into a qoa_test_samples directory.

@(private)
_wav_data := [][]runtime.Load_Directory_File{
    // #load_directory("qoa_test_samples/oculus_audio_pack"),
    // #load_directory("qoa_test_samples/sqam"),
}

@(private)
_qoa_data := [][]runtime.Load_Directory_File{
    // #load_directory("qoa_test_samples/oculus_audio_pack/qoa"),
    // #load_directory("qoa_test_samples/sqam/qoa"),
}

@(test)
_file_sanity_test :: proc(t: ^testing.T) {
    testing.expect(t, len(_wav_data) == len(_qoa_data))
    for dir, i in _wav_data {
        testing.expect(t, len(dir) == len(_qoa_data[i]))

        for file, j in dir {
            testing.expect(t, len(strings.common_prefix(file.name, _qoa_data[i][j].name)) > 5)
        }
    }
}

@(test)
_encode_test :: proc(t: ^testing.T) {
    for dir, i in _wav_data {
        for file, j in dir {
            defer free_all(context.temp_allocator)

            wav_header, wav_data, wav_ok := wav.decode_header(file.data)
            testing.expect(t, wav_ok)

            samples := wav.decode_samples(wav_header.format, wav_data, context.temp_allocator)

            samples_i16 := make([]i16, len(samples), context.temp_allocator)
            for &s, i in samples_i16 {
                s = pack_sample(samples[i])
            }

            desc := Desc{
                sample_rate = wav_header.format.sample_rate,
                num_channels = u32(wav_header.format.num_channels),
            }

            log.info(file.name, desc.sample_rate, len(samples), desc.num_channels)

            qoa_enc, qoa_ok := encode(&desc, samples_i16, context.temp_allocator)
            testing.expect(t, qoa_ok)

            qoa_src := _qoa_data[i][j].data

            testing.expect(t, len(qoa_enc) == len(qoa_src))
            if !testing.expect(t, mem.compare(qoa_enc, qoa_src) == 0) {
                // for x, i in soa_zip(a = qoa_enc, b = qoa_src) {
                //     if x.a != x.b {
                //         log.errorf("Byte %i is wrong: %x vs %x", i, x.a, x.b)
                //     }
                // }
            }
        }
    }
}

@(test)
_decode_test :: proc(t: ^testing.T) {
    for dir, i in _wav_data {
        for file, j in dir {
            defer free_all(context.temp_allocator)

            // 1. Get ground truth from WAV
            wav_header, wav_data, wav_ok := wav.decode_header(file.data)
            testing.expect(t, wav_ok)
            samples := wav.decode_samples(wav_header.format, wav_data, context.temp_allocator)

            // Convert to i16 (The "Expected" result)
            expected_samples := make([]i16, len(samples), context.temp_allocator)
            for s, idx in samples {
                expected_samples[idx] = pack_sample(s)
            }

            qoa_src := _qoa_data[i][j].data

            desc, decoded_samples, decode_ok := decode(qoa_src, context.temp_allocator)

            testing.expectf(t, decode_ok, "Failed to decode: %s", file.name)

            testing.expect(t, desc.samples > 0)
            testing.expect(t, desc.num_channels > 0)
            testing.expect(t, desc.sample_rate > 0)
            // testing.expect(t, desc.samples == u32(len(samples)) / u32(wav_header.format.num_channels))
            testing.expect(t, desc.num_channels == u32(wav_header.format.num_channels))
            testing.expect(t, desc.sample_rate == wav_header.format.sample_rate)

            // 4. Compare Samples
            // Note: QOA is lossy. Comparing exactly with mem.compare will likely fail.
            // We check length and sample-wise delta if necessary.
            testing.expectf(t, len(decoded_samples) == len(expected_samples),
                "%s: length mismatch. Got %d, want %d", file.name, len(decoded_samples), len(expected_samples))

            sum_diff: i64 = 0
            for s, i in decoded_samples {
                diff := abs(i32(s) - i32(expected_samples[i]))
                sum_diff += i64(diff)
            }
            log.infof("%s: Average sample delta: %f", file.name, f64(sum_diff) / f64(desc.samples))
        }
    }
}

@(test)
_stream_decode_matches_full :: proc(t: ^testing.T) {
    for num_channels in u32(1)..=2 {
        // A few full frames plus a short trailing frame, so we cover both cases.
        total_samples := FRAME_LEN * 3 + 137
        src := make([]i16, total_samples * int(num_channels), context.temp_allocator)
        for i in 0..<total_samples {
            for c in 0..<int(num_channels) {
                phase := f64(i) * (0.03 + 0.01 * f64(c))
                v := math.sin(phase) * 0.6 + math.sin(phase * 4.3) * 0.3
                src[i * int(num_channels) + c] = i16(v * 30000.0)
            }
        }

        enc_desc := Desc{ sample_rate = 44100, num_channels = num_channels }
        enc, enc_ok := encode(&enc_desc, src, context.temp_allocator)
        testing.expect(t, enc_ok)

        dec_desc, full, dec_ok := decode(enc, context.temp_allocator)
        testing.expect(t, dec_ok)
        testing.expect(t, dec_desc.samples == u32(total_samples))
        testing.expect(t, dec_desc.num_channels == num_channels)

        num_frames := (total_samples + FRAME_LEN - 1) / FRAME_LEN
        buf := make([]i16, FRAME_LEN * int(num_channels), context.temp_allocator)

        for f in 0..<num_frames {
            // Poison the buffer so we know decode_frame_index actually wrote it.
            for &b in buf { b = -12345 }

            n := decode_frame_index(enc, num_channels, dec_desc.sample_rate, f, buf)
            testing.expectf(t, n > 0, "frame %d failed to decode", f)

            expected_n := min(FRAME_LEN, total_samples - f * FRAME_LEN)
            testing.expectf(t, int(n) == expected_n, "frame %d: got %d samples, want %d", f, n, expected_n)

            base := f * FRAME_LEN * int(num_channels)
            for i in 0..<int(n) * int(num_channels) {
                testing.expectf(t, buf[i] == full[base + i],
                    "ch=%d frame=%d idx=%d: stream=%d full=%d", num_channels, f, i, buf[i], full[base + i])
            }
        }
    }
}

@(test)
_stream_decode_out_of_range :: proc(t: ^testing.T) {
    src := make([]i16, FRAME_LEN * 2, context.temp_allocator) // 1 full frame, stereo
    enc_desc := Desc{ sample_rate = 22050, num_channels = 2 }
    enc, enc_ok := encode(&enc_desc, src, context.temp_allocator)
    testing.expect(t, enc_ok)

    buf := make([]i16, FRAME_LEN * 2, context.temp_allocator)
    testing.expect(t, decode_frame_index(enc, 2, 22050, 0, buf) > 0)   // valid
    testing.expect(t, decode_frame_index(enc, 2, 22050, 1, buf) == 0)  // past end
    testing.expect(t, decode_frame_index(enc, 2, 22050, -1, buf) == 0) // negative
}
