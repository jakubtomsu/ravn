#+vet explicit-allocators shadowing unused
package qoa

max_frame_size :: proc(desc: ^Desc) -> int {
    return _frame_size(int(desc.num_channels), SLICES_PER_FRAME)
}

decode_info :: proc(data: []byte) -> (desc: Desc, ok: bool) {
    buf: Buffer = { data = data }
    return decode_header(&buf)
}

decode_frame_index :: proc(data: []byte, num_channels: u32, sample_rate: u32, frame_index: int, sample_data: []i16) -> u32 {
    if num_channels == 0 || frame_index < 0 {
        return 0
    }

    frame_size := _frame_size(int(num_channels), SLICES_PER_FRAME)
    offs := 8 + frame_index * frame_size

    if offs + 8 > len(data) {
        return 0
    }

    desc: Desc = {
        num_channels = num_channels,
        sample_rate  = sample_rate,
    }
    buf: Buffer = {
        data = data,
        offs = u64(offs),
    }

    return decode_frame(&buf, &desc, sample_data)
}

decode :: proc(data: []byte, allocator := context.allocator) -> (desc: Desc, result: []i16, ok: bool) {
    buf: Buffer = {
        data = data,
        offs = 0,
    }

    desc, ok = decode_header(&buf)
    if !ok {
        log(.Error, "QOA: Failed to decode header")
        return {}, nil, false
    }

    // Calculate the required size of the sample buffer and allocate
    result = make([]i16, desc.samples * desc.num_channels, allocator = allocator)

    sample_index: u32 = 0

    // Decode all frames
    for {
        samples := result[sample_index * desc.num_channels:]
        frame_len := decode_frame(&buf, &desc, sample_data = samples)
        sample_index += frame_len

        if frame_len == 0 || sample_index >= desc.samples {
            break
        }
    }

    assert(sample_index == desc.samples)

    desc.samples = sample_index
    return desc, result, true
}

decode_header :: proc(buf: ^Buffer) -> (desc: Desc, ok: bool) {
    if len(buf.data[buf.offs:]) < MIN_FILESIZE {
        log(.Error, "QOA: Input buffer is too small to decode a header")
        return {}, false
    }

    // Read the file header, verify the magic number ('qoaf') and read the
    // total number of samples.
    file_header := read_u64(buf)

    if u32(file_header >> 32) != MAGIC {
        log(.Error, "QOA: Header magic mismatch")
        return {}, false
    }

    desc.samples = u32(file_header & 0xffffffff)
    if desc.samples == 0 {
        log(.Error, "QOA: Streaming not supported")
        return {}, false
    }

    // Peek into the first frame header to get the number of num_channels and
    // the sample_rate.
    frame_header := read_u64(buf)
    desc.num_channels   = u32(frame_header >> 56) & 0x0000ff
    desc.sample_rate = u32(frame_header >> 32) & 0xffffff

    if desc.num_channels == 0 || desc.samples == 0 || desc.sample_rate == 0 {
        log(.Error, "QOA: Invalid header parameters")
        return {}, false
    }

    buf.offs = 8 // continue right after the header

    return desc, true
}

decode_frame :: proc(buf: ^Buffer, desc: ^Desc, sample_data: []i16) -> u32 {
    size := len(buf.data[buf.offs:])
    if u32(size) < 8 + LMS_LEN * 4 * desc.num_channels {
        log(.Error, "QOA: Input buffer is too small to decode a frame")
        return 0
    }

    // Read and verify the frame header
    frame_header := read_u64(buf)
    num_channels   := u32(frame_header >> 56) & 0x0000ff
    sample_rate := u32(frame_header >> 32) & 0xffffff
    samples    := u32(frame_header >> 16) & 0x00ffff
    frame_size := u32(frame_header      ) & 0x00ffff

    data_size: u32 = frame_size - 8 - LMS_LEN * 4 * num_channels
    num_slices: u32 = data_size / 8
    max_total_samples: u32 = num_slices * SLICE_LEN

    if
        num_channels != desc.num_channels ||
        sample_rate != desc.sample_rate ||
        int(frame_size) > size ||
        samples * num_channels > max_total_samples
    {
        log(.Error, "QOA: Invalid frame parameters")
        return 0
    }

    // Read the LMS state: 4 x 2 bytes history, 4 x 2 bytes weights per channel
    for c in 0..<num_channels {
        history := read_u64(buf)
        weights := read_u64(buf)
        for i in 0..<LMS_LEN {
            desc.lms[c].history[i] = i32(transmute(i16)(u16(history >> 48)))
            history <<= 16
            desc.lms[c].weights[i] = i32(transmute(i16)(u16(weights >> 48)))
            weights <<= 16
        }
    }

    // Decode all slices for all num_channels in this frame
    for sample_index := 0; sample_index < int(samples); sample_index += SLICE_LEN {
        for c in 0..<int(num_channels) {
            slice := read_u64(buf)

            scalefactor := i32((slice >> 60) & 0xf)
            slice <<= 4

            slice_start := sample_index * int(num_channels) + c
            slice_end := clamp(sample_index + SLICE_LEN, 0, int(samples)) * int(num_channels) + c

            for si := slice_start; si < slice_end; si += int(num_channels) {
                predicted := lms_predict(desc.lms[c])
                quantized := i32((slice >> 61) & 0x7)
                dequantized := _dequant_tab[scalefactor][quantized]
                reconstructed := clamp_s16(predicted + dequantized)

                sample_data[si] = i16(reconstructed)
                slice <<= 3

                lms_update(&desc.lms[c], reconstructed, dequantized)
            }
        }
    }

    return samples
}
