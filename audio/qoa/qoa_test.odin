#+test
package qoa

import "core:mem"
import "base:runtime"
import "core:testing"
import "core:log"
import "core:strings"
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