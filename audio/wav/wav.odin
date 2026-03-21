#+vet explicit-allocators
package audio_wav

import "base:runtime"

RIFF_CHUNK_ID: [4]byte: "RIFF"
FORMAT_CHUNK_ID: [4]byte: "fmt "
DATA_CHUNK_ID: [4]byte: "data"

FILE_FORMAT_ID: [4]byte: "WAVE"

// https://en.wikipedia.org/wiki/WAV
Header :: struct {
    riff:   RIFF_Chunk,
    format: Format_Chunk,
    data:   Data_Chunk,
}

Chunk :: struct {
    id:     [4]byte,
    size:   u32,
}

RIFF_Chunk :: struct {
    using chunk:        Chunk, // RIFF_CHUNK_ID + Overall file size minus 8 bytes
    file_format_id:     [4]byte, // FILE_FORMAT_ID
}

Format_Chunk :: struct {
    using chunk:        Chunk, // FORMAT_CHUNK_ID + Chunk size minus 8 bytes, which is 16 bytes here (0x10)
    format:             Format,
    num_channels:       u16,
    sample_rate:        u32, // Sample rate frequency in hertz
    byte_per_sec:       u32, // Number of bytes to read per second (Frequency * BytePerBloc).
    byte_per_bloc:      u16, // Number of bytes per block (NbrChannels * BitsPerSample / 8).
    bits_per_sample:    u16, // Number of bits per sample
}

Data_Chunk :: struct {
    using chunk:    Chunk, // DATA_CHUNK_ID + sample data size
}

Format :: enum u16 {
    Invalid = 0,
    PCM_Integer = 1,
    IEEE_754_Float = 3,
}

@(require_results)
decode :: proc(data: []byte, allocator := context.allocator) -> (header: Header, samples: []f32, ok: bool) {
    sample_bytes: []byte
    header, sample_bytes, ok = decode_header(data)
    if !ok {
        log(.Error, "WAV: Failed to decode header")
    }

    samples = decode_samples(header.format, sample_bytes, allocator = allocator)

    return header, samples, true
}

@(require_results)
decode_header :: proc(data: []byte) -> (result: Header, result_data: []byte, ok: bool) {
    if len(data) < size_of(Header) {
        log(.Error, "WAV: Data is too small")
        return {}, nil, false
    }

    result.riff = (cast(^RIFF_Chunk)raw_data(data))^

    if result.riff.id != RIFF_CHUNK_ID || result.riff.file_format_id != FILE_FORMAT_ID {
        log(.Error, "WAV: RIFF Header magic mismatch")
        return {}, nil, false
    }

    if int(result.riff.size) + 8 > len(data) {
        log(.Error, "WAV: File size doesn't match header")
        return result, nil, false
    }

    offset := size_of(RIFF_Chunk)

    for offset + size_of(Chunk) < len(data) {
        chunk := (cast(^Chunk)&data[offset])

        switch chunk.id {
        case FORMAT_CHUNK_ID:
            result.format = (cast(^Format_Chunk)&data[offset])^

        case DATA_CHUNK_ID:
            result.data = (cast(^Data_Chunk)&data[offset])^

            if result.format == {} {
                log(.Error, "WAV: Format chunk must come before data chunk")
                return result, nil, false
            }

            result_data = data[offset + size_of(Chunk):][:result.data.size]
            ok = true

        case:
            // probably a JUNK or some other unimportant chunk
        }

        offset += size_of(Chunk) + int(chunk.size)
    }

    return result, result_data, ok
}

@(require_results)
decode_samples :: proc(format: Format_Chunk, data: []byte, allocator := context.allocator) -> (result: []f32) {
    switch format.format {
    case .Invalid: fallthrough
    case:
        panic("Unsupported WAV format")

    case .PCM_Integer:
        switch format.bits_per_sample {
        case 8:  // u8, 0..255 with 128 as center
            result = make([]f32, len(data), allocator)

            for i in 0..<len(result) {
                result[i] = (f32(data[i]) - 128.0) * (1.0 / 255.0)
            }

        case 16: // i16, -32768..32767 with 0 as center
            assert(len(data) % 2 == 0)

            data16 := reinterpret_bytes(i16, data)
            result = make([]f32, len(data16), allocator)

            for i in 0..<len(result) {
                result[i] = f32(data16[i]) * (1.0 / 32768.0)
            }

        case 24:
            assert(len(data) % 3 == 0)
            result = make([]f32, len(data) / 3, allocator)

            for i in 0..<len(result) {
                val := i32(
                    (u32(data[i*3 + 0]) << 8 ) |
                    (u32(data[i*3 + 1]) << 16) |
                    (u32(data[i*3 + 2]) << 24)) >> 8 // arithmetic shift to sign extend

                result[i] = f32(val) * (1.0 / 8388608.0) // Normalize using 2^23
            }

        case:
            panic("Not supported")
        }

    case .IEEE_754_Float:
        switch format.bits_per_sample {
        case 32:
            return reinterpret_bytes(f32, data)

        case:
            panic("Not supported")
        }
    }

    return result
}

// Initialize a header for writing it to a file.
// To encode a WAV file, write the header immediately followed by the raw sample bytes.
@(require_results)
init_header :: proc(header: ^Header, sample_rate: u32, num_channels: u16, sample_size: u32, sample_format: Format, data: []byte) {
    header^ = {
        riff = RIFF_Chunk{
            chunk = {
                id = RIFF_CHUNK_ID,
                size = len(data) - size_of(Chunk),
            },
            file_format_id = FILE_FORMAT_ID,
        },
        format = Format_Chunk{
            chunk = {
                id = FORMAT_CHUNK_ID,
                size = size_of(Format_Chunk) - size_of(Chunk),
            },
            format = format,,
            num_channels = num_channels,
            sample_rate = sample_rate,
            byte_per_sec = u32(sample_rate) * sample_size,
            byte_per_bloc = u32(num_channels) * sample_size,
            bits_per_sample = sample_size * 8,
        },
        data = Data_Chunk{
            chunk = {
                id = DATA_CHUNK_ID,
                size = len(data),
            },
        },
    }
}

@(require_results)
reinterpret_bytes :: proc "contextless" ($T: typeid, bytes: []byte) -> []T {
    n := len(bytes) / size_of(T)
    assert_contextless(n * size_of(T) == len(bytes))
    return ([^]T)(raw_data(bytes))[:n]
}

log :: proc(level: runtime.Logger_Level, str: string, loc := #caller_location) {
    if context.logger.procedure == nil || level < context.logger.lowest_level {
        return
    }
    context.logger.procedure(context.logger.data, level, str, context.logger.options, location = loc)
}
