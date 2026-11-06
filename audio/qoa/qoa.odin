/*
Quite OK Audio format
Fast, lossy compression

https://qoaformat.org/

Implementation based on https://github.com/phoboslab/qoa/blob/master/qoa.h
Licensed under MIT, see https://github.com/phoboslab/qoa/blob/master/LICENSE

Code used for testing:
https://gist.github.com/jakubtomsu/ec8675231e6cf19e04bfaa20cc7e19f8

Original Documentation:

Copyright (c) 2023, Dominic Szablewski - https://phoboslab.org
SPDX-License-Identifier: MIT

QOA - The "Quite OK Audio" format for fast, lossy audio compression


-- Data Format

QOA encodes pulse-code modulated (PCM) audio data with up to 255 channels,
sample rates from 1 up to 16777215 hertz and a bit depth of 16 bits.

The compression method employed in QOA is lossy; it discards some information
from the uncompressed PCM data. For many types of audio signals this compression
is "transparent", i.e. the difference from the original file is often not
audible.

QOA encodes 20 samples of 16 bit PCM data into slices of 64 bits. A single
sample therefore requires 3.2 bits of storage space, resulting in a 5x
compression (16 / 3.2).

A QOA file consists of an 8 byte file header, followed by a number of frames.
Each frame contains an 8 byte frame header, the current 16 byte en-/decoder
state per channel and 256 slices per channel. Each slice is 8 bytes wide and
encodes 20 samples of audio data.

All values, including the slices, are big endian. The file layout is as follows:

struct {
    struct {
        char     magic[4];         // magic bytes "qoaf"
        uint32_t samples;          // samples per channel in this file
    } file_header;

    struct {
        struct {
            uint8_t  num_channels; // no. of channels
            uint24_t sample_rate;   // sample_rate in hz
            uint16_t fsamples;     // samples per channel in this frame
            uint16_t fsize;        // frame size (includes this header)
        } frame_header;

        struct {
            int16_t history[4];    // most recent last
            int16_t weights[4];    // most recent last
        } lms_state[num_channels];

        qoa_slice_t slices[256][num_channels];

    } frames[ceil(samples / (256 * 20))];
} qoa_file_t;

Each `qoa_slice_t` contains a quantized scalefactor `sf_quant` and 20 quantized
residuals `qrNN`:

.- QOA_SLICE -- 64 bits, 20 samples --------------------------/  /------------.
|        Byte[0]         |        Byte[1]         |  Byte[2]  \  \  Byte[7]   |
| 7  6  5  4  3  2  1  0 | 7  6  5  4  3  2  1  0 | 7  6  5   /  /    2  1  0 |
|------------+--------+--------+--------+---------+---------+-\  \--+---------|
|  sf_quant  |  qr00  |  qr01  |  qr02  |  qr03   |  qr04   | /  /  |  qr19   |
`-------------------------------------------------------------\  \------------`

Each frame except the last must contain exactly 256 slices per channel. The last
frame may contain between 1 .. 256 (inclusive) slices per channel. The last
slice (for each channel) in the last frame may contain less than 20 samples; the
slice still must be 8 bytes wide, with the unused samples zeroed out.

Channels are interleaved per slice. E.g. for 2 channel stereo:
slice[0] = L, slice[1] = R, slice[2] = L, slice[3] = R ...

A valid QOA file or stream must have at least one frame. Each frame must contain
at least one channel and one sample with a sample_rate between 1 .. 16777215
(inclusive).

If the total number of samples is not known by the encoder, the samples in the
file header may be set to 0x00000000 to indicate that the encoder is
"streaming". In a streaming context, the sample_rate and number of channels may
differ from frame to frame. For static files (those with samples set to a
non-zero value), each frame must have the same number of channels and same
sample_rate.

Note that this implementation of QOA only handles files with a known total
number of samples.

A decoder should support at least 8 channels. The channel layout for channel
counts 1 .. 8 is:

    1. Mono
    2. L, R
    3. L, R, C
    4. FL, FR, B/SL, B/SR
    5. FL, FR, C, B/SL, B/SR
    6. FL, FR, C, LFE, B/SL, B/SR
    7. FL, FR, C, LFE, B, SL, SR
    8. FL, FR, C, LFE, BL, BR, SL, SR

QOA predicts each audio sample based on the previously decoded ones using a
"Sign-Sign Least Mean Squares Filter" (LMS). This prediction plus the
dequantized residual forms the final output sample.

*/
#+vet explicit-allocators shadowing unused
package qoa

MIN_FILESIZE :: 16
MAX_CHANNELS :: 8

SLICE_LEN :: 20
SLICES_PER_FRAME :: 256
FRAME_LEN :: SLICES_PER_FRAME * SLICE_LEN
LMS_LEN :: 4
MAGIC :: 0x716f6166 // "qoaf"

RECORD_TOTAL_ERROR :: #config(RECORD_TOTAL_ERROR, false)

// Least-mean squares filter
LMS :: struct {
    history: [LMS_LEN]i32,
    weights: [LMS_LEN]i32,
}

Desc :: struct {
    num_channels:   u32,
    sample_rate:    u32,
    samples:        u32,
    lms:            [MAX_CHANNELS]LMS,
    error:          f64, // only used when RECORD_TOTAL_ERROR=true
}


_frame_size :: proc(channels: int, slices: int) -> int {
    return 8 + LMS_LEN * 4 * channels + 8 * slices * channels
}



/* The quant_tab provides an index into the dequant_tab for residuals in the
range of -8 .. 8. It maps this range to just 3bits and becomes less accurate at
the higher end. Note that the residual zero is identical to the lowest positive
value. This is mostly fine, since the div() function always rounds away
from zero. */

@(rodata)
_quant_tab := [17]i32{
    7, 7, 7, 5, 5, 3, 3, 1, /* -8..-1 */
    0,                      /*  0     */
    0, 2, 2, 4, 4, 6, 6, 6  /*  1.. 8 */
}


/* We have 16 different scalefactors. Like the quantized residuals these become
less accurate at the higher end. In theory, the highest scalefactor that we
would need to encode the highest 16bit residual is (2**16)/8 = 8192. However we
rely on the LMS filter to predict samples accurately enough that a maximum
residual of one quarter of the 16 bit range is sufficient. I.e. with the
scalefactor 2048 times the quant range of 8 we can encode residuals up to 2**14.

The scalefactor values are computed as:
scalefactor_tab[s] <- round(pow(s + 1, 2.75)) */

@(rodata)
_scalefactor_tab := [16]i32{
    1, 7, 21, 45, 84, 138, 211, 304, 421, 562, 731, 928, 1157, 1419, 1715, 2048
}


/* The reciprocal_tab maps each of the 16 scalefactors to their rounded
reciprocals 1/scalefactor. This allows us to calculate the scaled residuals in
the encoder with just one multiplication instead of an expensive division. We
do this in .16 fixed point with integers, instead of floats.

The reciprocal_tab is computed as:
reciprocal_tab[s] <- ((1<<16) + scalefactor_tab[s] - 1) / scalefactor_tab[s] */

@(rodata)
_reciprocal_tab := [16]i32{
    65536, 9363, 3121, 1457, 781, 475, 311, 216, 156, 117, 90, 71, 57, 47, 39, 32
}


/* The dequant_tab maps each of the scalefactors and quantized residuals to
their unscaled & dequantized version.

Since div rounds away from the zero, the smallest entries are mapped to 3/4
instead of 1. The dequant_tab assumes the following dequantized values for each
of the quant_tab indices and is computed as:
float dqt[8] = {0.75, -0.75, 2.5, -2.5, 4.5, -4.5, 7, -7}
dequant_tab[s][q] <- round_ties_away_from_zero(scalefactor_tab[s] * dqt[q])

The rounding employed here is "to nearest, ties away from zero",  i.e. positive
and negative values are treated symmetrically.
*/

@(rodata)
_dequant_tab := [16][8]i32{
    {   1,    -1,    3,    -3,    5,    -5,     7,     -7},
    {   5,    -5,   18,   -18,   32,   -32,    49,    -49},
    {  16,   -16,   53,   -53,   95,   -95,   147,   -147},
    {  34,   -34,  113,  -113,  203,  -203,   315,   -315},
    {  63,   -63,  210,  -210,  378,  -378,   588,   -588},
    { 104,  -104,  345,  -345,  621,  -621,   966,   -966},
    { 158,  -158,  528,  -528,  950,  -950,  1477,  -1477},
    { 228,  -228,  760,  -760, 1368, -1368,  2128,  -2128},
    { 316,  -316, 1053, -1053, 1895, -1895,  2947,  -2947},
    { 422,  -422, 1405, -1405, 2529, -2529,  3934,  -3934},
    { 548,  -548, 1828, -1828, 3290, -3290,  5117,  -5117},
    { 696,  -696, 2320, -2320, 4176, -4176,  6496,  -6496},
    { 868,  -868, 2893, -2893, 5207, -5207,  8099,  -8099},
    {1064, -1064, 3548, -3548, 6386, -6386,  9933,  -9933},
    {1286, -1286, 4288, -4288, 7718, -7718, 12005, -12005},
    {1536, -1536, 5120, -5120, 9216, -9216, 14336, -14336},
}


/* The Least Mean Squares Filter is the heart of QOA. It predicts the next
sample based on the previous 4 reconstructed samples. It does so by continuously
adjusting 4 weights based on the residual of the previous prediction.

The next sample is predicted as the sum of (weight[i] * history[i]).

The adjustment of the weights is done with a "Sign-Sign-LMS" that adds or
subtracts the residual to each weight, based on the corresponding sample from
the history. This, surprisingly, is sufficient to get worthwhile predictions.

This is all done with fixed point integers. Hence the right-shifts when updating
the weights and calculating the prediction. */

lms_predict :: proc(lms: LMS) -> i32 {
    prediction: i64
    for i in 0..<LMS_LEN {
        prediction += i64(lms.weights[i]) * i64(lms.history[i])
    }
    return i32(prediction >> 13)
}

lms_update :: proc(lms: ^LMS, sample: i32, residual: i32) {
    delta := residual >> 4
    for i in 0..<LMS_LEN {
        lms.weights[i] += lms.history[i] < 0 ? -delta : delta
    }
    for i in 0..<LMS_LEN-1 {
        lms.history[i] = lms.history[i+1]
    }
    lms.history[LMS_LEN-1] = sample
}


/* div() implements a rounding division, but avoids rounding to zero for
small numbers. E.g. 0.1 will be rounded to 1. Note that 0 itself still
returns as 0, which is handled in the quant_tab[].
div() takes an index into the .16 fixed point reciprocal_tab as an
argument, so it can do the division with a cheaper integer multiplication. */

div :: proc(v: i32, scalefactor: i32) -> i32 {
    reciprocal := _reciprocal_tab[scalefactor]
    n := (v * reciprocal + (1 << 15)) >> 16
    n = n + (i32(v > 0) - i32(v < 0)) - (i32(n > 0) - i32(n < 0)) /* round away from 0 */
    return n
}

/* This specialized clamp function for the signed 16 bit range improves decode
performance quite a bit. The extra if() statement works nicely with the CPUs
branch prediction as this branch is rarely taken. */

clamp_s16 :: proc(v: i32) -> i32 {
    if u32(v + 32768) > 65535 {
        if v < -32768 { return -32768 }
        if v >  32767 { return  32767 }
    }
    return v
}

// RW byte buffer for encoding/decoding internals
Buffer :: struct {
    data:   []byte,
    offs:   u64,
}

read_u64 :: proc(buf: ^Buffer) -> u64 {
    data := buf.data[buf.offs:]
    buf.offs += 8
    result :=
        (u64(data[0]) << 56) | (u64(data[1]) << 48) |
        (u64(data[2]) << 40) | (u64(data[3]) << 32) |
        (u64(data[4]) << 24) | (u64(data[5]) << 16) |
        (u64(data[6]) <<  8) | (u64(data[7]) <<  0)
    return result
}

write_u64 :: proc(buf: ^Buffer, v: u64) {
    data := buf.data[buf.offs:]
    buf.offs += 8
    data[0] = u8((v >> 56) & 0xff)
    data[1] = u8((v >> 48) & 0xff)
    data[2] = u8((v >> 40) & 0xff)
    data[3] = u8((v >> 32) & 0xff)
    data[4] = u8((v >> 24) & 0xff)
    data[5] = u8((v >> 16) & 0xff)
    data[6] = u8((v >>  8) & 0xff)
    data[7] = u8((v >>  0) & 0xff)
}

pack_sample :: proc(val: f32) -> i16 {
    return i16(clamp(val * 32768.0, f32(min(i16)), f32(max(i16))))
}

unpack_sample :: proc(val: i16) -> f32 {
    return f32(val) * (1.0 / 32768.0)
}
