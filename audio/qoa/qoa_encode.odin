#+vet explicit-allocators shadowing unused
package qoa

import "core:log"

encode :: proc(desc: ^Desc, sample_data: []i16, allocator := context.allocator) -> (result: []byte, ok: bool) {
    if
        desc.samples != 0 ||
        len(sample_data) == 0 ||
        desc.num_channels == 0 || desc.num_channels > MAX_CHANNELS ||
        u32(len(sample_data)) % desc.num_channels != 0 ||
        desc.sample_rate == 0 || desc.sample_rate > 0xffffff
    {
        log.error("Invalid input desc")
        return nil, false
    }

    desc.samples = u32(len(sample_data)) / desc.num_channels

    // Calculate the encoded size and allocate
    num_frames := (desc.samples + FRAME_LEN-1) / FRAME_LEN
    num_slices := (desc.samples + SLICE_LEN-1) / SLICE_LEN
    encoded_size := 8 +                             // 8 byte file header
        num_frames * 8 +                            // 8 byte frame headers
        num_frames * LMS_LEN * 4 * desc.num_channels +  // 4 * 4 bytes lms state per channel
        num_slices * 8 * desc.num_channels              // 8 byte slices

    bytes := make([]byte, encoded_size, allocator)

    buf: Buffer = {
        data = bytes,
        offs = 0,
    }

    for c in 0..<desc.num_channels {
        // Set the initial LMS weights to {0, 0, -1, 2}.
        // This helps with the prediction of the first few ms of a file.
        desc.lms[c].weights[0] = 0
        desc.lms[c].weights[1] = 0
        desc.lms[c].weights[2] = -(1<<13)
        desc.lms[c].weights[3] =  (1<<14)

        // Explicitly set the history samples to 0, as we might have some garbage in there.
        desc.lms[c].history = {}
    }

    // Encode the header and go through all frames
    encode_header(&buf, desc.samples)
    if RECORD_TOTAL_ERROR {
        desc.error = 0
    }

    frame_len := FRAME_LEN
    for sample_index := 0; sample_index < int(desc.samples); sample_index += frame_len {
        frame_len = clamp(FRAME_LEN, 0, int(desc.samples) - sample_index)
        frame_samples := sample_data[sample_index * int(desc.num_channels):]
        encode_frame(&buf, desc, sample_data = frame_samples, frame_len = frame_len)
    }

    return buf.data[:buf.offs], true
}

encode_header :: proc(buf: ^Buffer, num_samples: u32) {
    write_u64(buf, (u64(MAGIC) << 32) | u64(num_samples))
}

encode_frame :: proc(buf: ^Buffer, desc: ^Desc, sample_data: []i16, frame_len: int) {
    num_channels := int(desc.num_channels)

    slices := (frame_len + SLICE_LEN - 1) / SLICE_LEN
    frame_size := _frame_size(num_channels, slices)
    prev_scalefactor: [MAX_CHANNELS]i32

    // Write the frame header
    write_u64(buf,
        u64(desc.num_channels)   << 56 |
        u64(desc.sample_rate) << 32 |
        u64(frame_len)       << 16 |
        u64(frame_size)
    )

    for c in 0..<num_channels {
        // Write the current LMS state
        weights: u64
        history: u64
        for i in 0..<LMS_LEN {
            history = (history << 16) | u64(desc.lms[c].history[i] & 0xffff)
            weights = (weights << 16) | u64(desc.lms[c].weights[i] & 0xffff)
        }
        write_u64(buf, history)
        write_u64(buf, weights)
    }

    // We encode all samples with the num_channels interleaved on a slice level.
    // E.g. for stereo: (ch-0, slice 0), (ch 1, slice 0), (ch 0, slice 1), ...
    for sample_index := 0; sample_index < frame_len; sample_index += SLICE_LEN {
        for c in 0..<num_channels {
            slice_len := clamp(SLICE_LEN, 0, frame_len - sample_index)
            slice_start := sample_index * num_channels + c
            slice_end := (sample_index + slice_len) * num_channels + c

            // Brute force search for the best scalefactor. Just go through all
            // 16 scalefactors, encode all samples for the current slice and
            // meassure the total squared error.
            best_rank: u64 = max(u64)
            best_error: u64 = max(u64)
            best_slice: u64 = 0
            best_lms: LMS
            best_scalefactor: i32 = 0

            for sfi in 0..<i32(16) {
                /* There is a strong correlation between the scalefactors of
                neighboring slices. As an optimization, start testing
                the best scalefactor of the previous slice first. */
                scalefactor := (sfi + prev_scalefactor[c]) & (16 - 1)

                /* We have to reset the LMS state to the last known good one
                before trying each scalefactor, as each pass updates the LMS
                state when encoding. */
                lms := desc.lms[c]
                slice := u64(scalefactor)
                current_rank: u64 = 0
                current_error: u64 = 0

                for si := slice_start; si < slice_end; si += num_channels {
                    sample := sample_data[si]
                    predicted := lms_predict(lms)
                    residual := i32(sample) - predicted
                    scaled := div(residual, scalefactor)
                    clamped := clamp(scaled, -8, 8)
                    quantized := _quant_tab[clamped + 8]
                    dequantized := _dequant_tab[scalefactor][quantized]
                    reconstructed := clamp_s16(predicted + dequantized)

                    /* If the weights have grown too large, we introduce a penalty
                    here. This prevents pops/clicks in certain problem cases */
                    weights_penalty := ((
                        i64(lms.weights[0]) * i64(lms.weights[0]) +
                        i64(lms.weights[1]) * i64(lms.weights[1]) +
                        i64(lms.weights[2]) * i64(lms.weights[2]) +
                        i64(lms.weights[3]) * i64(lms.weights[3])
                    ) >> 18) - 0x8ff

                    if weights_penalty < 0 {
                        weights_penalty = 0
                    }

                    error := i64(sample) - i64(reconstructed)
                    error_sq := u64(error * error)

                    current_rank += error_sq + u64(weights_penalty) * u64(weights_penalty)
                    current_error += u64(error_sq)
                    if current_rank > best_rank {
                        break
                    }

                    lms_update(&lms, reconstructed, dequantized)
                    slice = (slice << 3) | u64(quantized)
                }

                if current_rank < best_rank {
                    best_rank = current_rank
                    best_error = current_error
                    best_slice = slice
                    best_lms = lms
                    best_scalefactor = scalefactor
                }
            }

            prev_scalefactor[c] = best_scalefactor

            desc.lms[c] = best_lms
            if RECORD_TOTAL_ERROR {
                desc.error += f64(best_error)
            }

            /* If this slice was shorter than SLICE_LEN, we have to left-
            shift all encoded data, to ensure the rightmost bits are the empty
            ones. This should only happen in the last frame of a file as all
            slices are completely filled otherwise. */
            best_slice <<= uint(SLICE_LEN - slice_len) * 3
            write_u64(buf, best_slice)
        }
    }
}
