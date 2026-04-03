#+vet explicit-allocators shadowing
package raven_audio

// TODO: this package could be completely self contained, no base dependency.

import "../base"
import "base:intrinsics"
import "base:runtime"
import "core:math"

import "wav"
// import "qoa"

// TODO: sound fading
// TODO: sound trim range for dynamically chopping big sounds
// one pole filter

BACKEND :: #config(AUDIO_BACKEND, BACKEND_DEFAULT)

BACKEND_NONE :: "None"
BACKEND_WASAPI :: "WASAPI"
BACKEND_WEBAUDIO :: "WebAudio"
BACKEND_MINIAUDIO :: "miniaudio"
BACKEND_SDL3 :: "SDL3"

when ODIN_OS == .Windows {
    BACKEND_DEFAULT :: BACKEND_WASAPI
} else when ODIN_OS == .JS {
    BACKEND_DEFAULT :: BACKEND_WEBAUDIO
} else {
    BACKEND_DEFAULT :: BACKEND_MINIAUDIO
}

// Has no effect on some backends.
SINGLE_THREAD :: #config(AUDIO_SINGLE_THREAD, false)

MAX_SOUNDS :: #config(AUDIO_MAX_SOUNDS, 512)
MAX_RESOURCES :: #config(AUDIO_MAX_RESOURCE, 256)
NUM_GROUPS :: 8
SCRATCH_FRAMES :: 1024 * 2
SPEED_OF_SOUND :: 343 // m/s, dry air at around 20C

Handle_Index :: u16
Handle_Gen :: u8

// Zero value means invalid handle
Handle :: struct {
    index:  u16,
    gen:    u8,
}

Resource_Handle :: distinct Handle
Sound_Handle :: distinct Handle

_state: ^State

State :: struct #align(64) {
    using native:       _State,
    running:            bool,
    init_context:       runtime.Context,
    frame_rate:         u32,

    master_mixer_proc:  Generator_Proc,

    listener_curr:      Listener,
    listener_prev:      Listener, // Audio thread access only

    resources_free:     SPSC(MAX_RESOURCES, Handle_Index),
    resources_state:    [MAX_RESOURCES]Slot_State,
    resources_gen:      [MAX_RESOURCES]Handle_Gen,
    resources:          [MAX_RESOURCES]Resource,

    sounds_free:        SPSC(MAX_SOUNDS, Handle_Index),
    sounds_state:       [MAX_SOUNDS]Slot_State,
    sounds_gen:         [MAX_SOUNDS]Handle_Gen,
    sounds:             [MAX_SOUNDS]Sound,

    groups:             [NUM_GROUPS]Group,
}

Generator_Proc :: #type proc(frames: [][2]f32, frame_rate: int)

// Atomic
Slot_State :: enum u32 {
    Free = 0,
    Used,
    Request_Free, // Always handled by audio thread
}

Group :: struct {
    sound_params:   [Sound_Param_Kind]Param,
}

GROUP_DEFAULT :: Group {
    sound_params = {
        // Scale params (Multiplicative)
        .Volume             = {1, 1, 1},
        .Pitch              = {1, 1, 1},
        .Doppler_Factor     = {1, 1, 1},
        .Attenuation_Min    = {1, 1, 1},
        .Attenuation_Max    = {1, 1, 1},

        // Offset params (Additive)
        .Pan                = {0, 0, 1},
        .Lowpass            = {0, 0, 1},
        .Highpass           = {0, 0, 1},
    },
}

// Represents the sample data.
Resource :: struct {
    data:           [^]byte,
    format:         Resource_Format,
    frame_num:      u32,
    frame_rate:     u32, // hz
    flags:          bit_set[Resource_Flag], // Only read by the Audio Thread
}

Resource_Flag :: enum u8 {
    Mono,
}

Resource_Format :: enum u8 {
    Invalid = 0,
    Raw_F32,
    Raw_I16,
    Raw_U8,
    WAV,
}

Sound :: struct {
    frame:              f64,
    delay:              f32,
    frame_range:        [2]u32,
    resource:           Resource_Handle,
    flags:              bit_set[Sound_Flag],
    group_index:        u8,

    playing:            b32,
    params:             [Sound_Param_Kind]Param,

    pos_curr:           [3]f32,
    pos_prev:           [3]f32,
    vel_curr:           [3]f32,
    vel_prev:           [3]f32,

    lpf_prev:           [2]f32,
    hpf_prev:           [2]f32,
}

Sound_Flag :: enum u8 {
    Loop,
    Spatial,
}

Sound_Param_Kind :: enum u8 {
    // Linear gain.
    //  0 = muted
    //  1 = default
    // >1 = louder
    Volume,

    // Raw speed factor.
    // Pitch of 2 will play the signal 2x faster.
    Pitch,

    // Shift sounds left/right
    //  0 = centered
    // -1 = hard left
    //  1 = hard right
    Pan,

    // Attenuation determines how sound volume chagnes with distance.
    Attenuation_Min,
    Attenuation_Max,

    // Muffles the sound.
    // Value of 0 means no filtering.
    // Alpha factor value in 0..1 range.
    Lowpass,

    // Sharpens the sound.
    // Value of 0 means no filtering.
    // Alpha factor value in 0..1 range.
    Highpass,

    // Doppler factor determines pitch change based on relative listener/sound velocity.
    // 1.0 is default
    Doppler_Factor,
}

// Smoothly updated parameter
Param :: struct {
    target: f32, // Game thread
    curr:   f32, // Audio thread
    delta:  f32, // Game thread
}

Listener :: struct {
    pos:    [3]f32,
    vel:    [3]f32,
    forw:   [3]f32,
    right:  [3]f32,
}

Unit :: enum u8 {
    Seconds = 0,
    Frames,
    Percentage, // 0..1
}



//////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Common
//

set_state_ptr :: proc(state: ^State) {
    _state = state
}

get_state_ptr :: proc() -> (state: ^State) {
    return _state
}

init :: proc(state: ^State) -> bool {
    if _state != nil {
        return true
    }

    _state = state

    _state.init_context = context
    _state.running = true

    for i in 1..<MAX_SOUNDS {
        base.spsc_push(&_state.sounds_free, Handle_Index(i))
    }

    for i in 1..<MAX_RESOURCES {
        base.spsc_push(&_state.resources_free, Handle_Index(i))
    }

    set_master_mixer(default_master_mixer)

    _state.groups = GROUP_DEFAULT

    if !_init() {
        return false
    }

    return true
}

shutdown :: proc() {
    if _state == nil {
        return
    }

    _state.running = false

    _shutdown()

    _state = nil
}

// Call every frame from the main thread.
update :: proc() {
    // On some platforms this does audio rendering on the main thread.
    // But on most backends, this is a no-op and everything is async.
    _render()
}

set_master_mixer :: proc(mixer: Generator_Proc) {
    intrinsics.atomic_store(&_state.master_mixer_proc, mixer)
}

set_listener :: proc(
    pos:    [3]f32,
    vel:    [3]f32,
    forw:   [3]f32 = {0, 0, 1},
    right:  [3]f32 = {1, 0, 0},
) {
    // This write isn't atomic as a whole, which could possibly result in small glitches
    // during very fast movement.
    atomic_store_components_release_vec(&_state.listener_curr.pos, pos)
    atomic_store_components_release_vec(&_state.listener_curr.vel, vel)
    atomic_store_components_release_vec(&_state.listener_curr.forw, forw)
    atomic_store_components_release_vec(&_state.listener_curr.right, right)
}



//////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Sounds
//

create_resource_mono_f32 :: proc(frames: []f32, frame_rate: u32) -> (result: Resource_Handle, ok: bool) {
    return create_resource(.Raw_F32, to_bytes(frames), flags = {.Mono}, frame_rate = frame_rate)
}

create_resource_stereo_f32 :: proc(frames: [][2]f32, frame_rate: u32) -> (result: Resource_Handle, ok: bool) {
    return create_resource(.Raw_F32, to_bytes(frames), flags = {}, frame_rate = frame_rate)
}

create_resource :: proc(
    format:         Resource_Format,
    data:           []byte,
    flags:          bit_set[Resource_Flag] = {},
    frame_rate:     u32 = 0,
) -> (result: Resource_Handle, ok: bool) {
    assert(format != .Invalid)

    index, index_ok := base.spsc_pop(&_state.resources_free)
    if !index_ok {
        base.log_err("No free sound resource slots")
        return {}, false
    }

    assert(intrinsics.atomic_load(&_state.resources_state[index]) == .Free)

    result = {
        index = index,
        gen = _state.resources_gen[index],
    }

    resource := &_state.resources[index]
    resource^ = {
        data = raw_data(data),
        format = format,
        frame_rate = frame_rate,
        flags = flags,
    }

    num_channels: u32 = .Mono in flags ? 1 : 2

    switch format {
    case .Invalid:
        assert(false)
        return

    case .Raw_F32:
        assert(frame_rate != 0)
        assert(len(data) % size_of(f32) == 0)
        resource.frame_num = u32(len(data)) / (num_channels * size_of(f32))

    case .Raw_I16:
        assert(frame_rate != 0)
        assert(len(data) % size_of(f32) == 0)
        resource.frame_num = u32(len(data)) / (num_channels * size_of(i16))

    case .Raw_U8:
        assert(frame_rate != 0)
        assert(len(data) % size_of(f32) == 0)
        resource.frame_num = u32(len(data)) / (num_channels * size_of(u8))

    case .WAV:
        header, sample_bytes, header_ok := wav.decode_header(data)
        if !header_ok {
            return {}, false
        }

        resource.data = raw_data(sample_bytes)
        resource.frame_num = u32(len(sample_bytes)) / u32(header.format.num_channels * (header.format.bits_per_sample / 8))
        resource.frame_rate = header.format.sample_rate

        switch header.format.format {
        case .Invalid:
            assert(false)

        case .PCM_Integer:
            switch header.format.bits_per_sample {
            case 8:
                resource.format = .Raw_U8

            case 16:
                resource.format = .Raw_I16

            case:
                return {}, false
            }

        case .IEEE_754_Float:
            if header.format.bits_per_sample != 32 {
                return {}, false
            }

            resource.format = .Raw_F32
        }

        switch header.format.num_channels {
        case 1: resource.flags += {.Mono}
        case 2: resource.flags -= {.Mono}
        case:
            assert(false, "Only WAV files with 1 or 2 channels are supported.")
            return {}, false
        }
    }

    assert(resource.frame_rate != 0)
    assert(resource.frame_num != 0)

    intrinsics.atomic_store(&_state.resources_state[index], .Used)

    return result, true
}

destroy_resource :: proc(handle: Resource_Handle) -> bool {
    if !is_resource_valid(handle) {
        return false
    }
    intrinsics.atomic_store(&_state.resources_state[handle.index], .Request_Free)
    return true
}

create_sound :: proc(
    resource_handle:        Resource_Handle,
    flags:                  bit_set[Sound_Flag] = {},
    pitch:                  f32 = 1.0,
    pan:                    f32 = 0,
    volume:                 f32 = 1,
    attenuation_range:      [2]f32 = {0.1, 100},
    lowpass:                f32 = 0.0,
    highpass:               f32 = 0.0,
    doppler_factor:         f32 = 1.0,
    playing                 := true,
    chop:                   [2]f32 = {0, 1},
    start_delay:            f32 = 0,
    pos:                    [3]f32 = 0,
    vel:                    [3]f32 = 0,
    #any_int group_index:   int = 0,
) -> (result: Sound_Handle, ok: bool) #optional_ok {
    assert(group_index >= 0)
    assert(group_index < NUM_GROUPS)

    index, index_ok := base.spsc_pop(&_state.sounds_free)
    if !index_ok {
        base.log_err("No free sound slots")
        return {}, false
    }

    res, res_ok := _get_resource(resource_handle)
    if !res_ok {
        base.log_err("Attempting to play sound with invalid resource handle %v", resource_handle)
        return {}, false
    }

    assert(intrinsics.atomic_load(&_state.sounds_state[index]) == .Free)
    assert(res.frame_rate > 0)
    assert(res.frame_num > 0)

    result = {
        index = index,
        gen = _state.sounds_gen[index],
    }

    sound := &_state.sounds[index]
    sound^ = {
        group_index = u8(group_index),
        resource = resource_handle,
        flags = flags,
        playing = b32(playing),
        frame = -f64(start_delay) * f64(res.frame_rate),
        frame_range = {
            u32(chop[0] * f32(res.frame_num)),
            u32(chop[1] * f32(res.frame_num)),
        },
        params = {
            .Pitch             = _param(pitch),
            .Volume            = _param(volume),
            .Pan               = _param(pan),
            .Attenuation_Min   = _param(attenuation_range[0]),
            .Attenuation_Max   = _param(attenuation_range[1]),
            .Doppler_Factor    = _param(doppler_factor),
            .Lowpass           = _param(lowpass),
            .Highpass          = _param(highpass),
        },
        pos_curr = pos,
        pos_prev = pos,
        vel_curr = vel,
        vel_prev = vel,
    }

    intrinsics.atomic_store(&_state.sounds_state[index], .Used)

    return result, true

    _param :: proc(p: f32) -> Param {
        return {
            target = p,
            curr = p,
            delta = 1,
        }
    }
}

destroy_sound :: proc(handle: Sound_Handle) -> bool {
    if !is_sound_valid(handle) {
        return false
    }
    intrinsics.atomic_store(&_state.sounds_state[handle.index], .Request_Free)
    return true
}

get_sound_time :: proc(handle: Sound_Handle, unit: Unit = .Seconds) -> f32 {
    sound, ok := _get_sound(handle)
    if !ok {
        return 0
    }

    frame_num := int(sound.frame_range[1]) - int(sound.frame_range[0])

    switch unit {
    case .Seconds:
        res, res_ok := _get_resource(sound.resource)
        if !res_ok {
            return 0
        }
        return f32(sound.frame) * f32(res.frame_rate)

    case .Frames:
        return f32(sound.frame) + f32(sound.frame_range[0])

    case .Percentage:
        return f32(sound.frame) / f32(frame_num)
    }

    return 0
}

get_sound_playing :: proc(handle: Sound_Handle) -> bool {
    sound, ok := _get_sound(handle)
    if !ok {
        return false
    }
    return bool(sound.playing)
}

set_sound_playing :: proc(handle: Sound_Handle, playing: bool) -> bool {
    sound := _get_sound(handle) or_return
    intrinsics.atomic_store_explicit(&sound.playing, b32(playing), .Release)
    return true
}

// Dur determines the time (in seconds) it takes to interpolate to the new value.
set_sound_param :: proc(handle: Sound_Handle, kind: Sound_Param_Kind, value: f32, dur: f32 = 0) -> bool {
    sound := _get_sound(handle) or_return
    intrinsics.atomic_store_explicit(&sound.params[kind].target, value, .Release)
    intrinsics.atomic_store_explicit(&sound.params[kind].delta, _duration_delta(dur), .Release)
    return true
}

set_group_sound_param :: proc(#any_int index: int, kind: Sound_Param_Kind, value: f32, dur: f32 = 0) -> bool {
    group := _get_group(index) or_return
    intrinsics.atomic_store_explicit(&group.sound_params[kind].target, value, .Release)
    intrinsics.atomic_store_explicit(&group.sound_params[kind].delta, _duration_delta(dur), .Release)
    return true
}

_duration_delta :: proc(dur: f32) -> f32 {
    return dur < 0.01 ? 1e6 : 1.0 / dur
}

set_sound_transform :: proc(handle: Sound_Handle, pos: [3]f32, vel: [3]f32) {
    sound, ok := _get_sound(handle)
    if !ok {
        return
    }
    atomic_store_components_release_vec(&sound.pos_curr, pos)
    atomic_store_components_release_vec(&sound.vel_curr, vel)
}

is_resource_valid :: proc(handle: Resource_Handle) -> bool {
    if handle.index <= 0 || handle.index >= MAX_RESOURCES {
        return false
    }

    if _state.resources_gen[handle.index] != handle.gen {
        return false
    }

    if intrinsics.atomic_load(&_state.resources_state[handle.index]) != .Used {
        return false
    }

    return true
}

is_sound_valid :: proc(handle: Sound_Handle) -> bool {
    if handle.index <= 0 || handle.index >= MAX_SOUNDS {
        return false
    }

    if _state.sounds_gen[handle.index] != handle.gen {
        return false
    }

    if intrinsics.atomic_load(&_state.sounds_state[handle.index]) != .Used {
        return false
    }

    return true
}

is_group_valid :: proc(#any_int index: int) -> bool {
    return index >= 0 && index < NUM_GROUPS
}

_get_resource :: proc(handle: Resource_Handle) -> (^Resource, bool) {
    if !is_resource_valid(handle) {
        return nil, false
    }
    return &_state.resources[handle.index], true
}

_get_sound :: proc(handle: Sound_Handle) -> (^Sound, bool) {
    if !is_sound_valid(handle) {
        return nil, false
    }
    return &_state.sounds[handle.index], true
}

_get_group :: proc(#any_int index: int) -> (^Group, bool) {
    if !is_group_valid(index) {
        return nil, false
    }
    return &_state.groups[index], true
}



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Mixer
//

default_master_mixer :: proc(out_buf: [][2]f32, frame_rate: int) {
    assert(_state.frame_rate >= 8000)
    assert(_state.frame_rate <= 192000)

    _scratch: [SCRATCH_FRAMES][2]f32
    scratch := _scratch[:len(out_buf)]

    listener_prev := _state.listener_prev

    listener_pos := atomic_load_components_acquire_vec(&_state.listener_curr.pos)
    listener_vel := atomic_load_components_acquire_vec(&_state.listener_curr.vel)
    listener_forw := atomic_load_components_acquire_vec(&_state.listener_curr.forw)
    listener_right := atomic_load_components_acquire_vec(&_state.listener_curr.right)

    atomic_store_components_release_vec(&_state.listener_prev.pos, listener_pos)
    _state.listener_prev.forw = listener_forw
    _state.listener_prev.right = listener_right
    _state.listener_prev.vel = listener_vel

    listener_up := normalize(cross(listener_forw, listener_right))
    listener_prev_up := normalize(cross(listener_prev.forw, listener_prev.right))

    global_delta_seconds := f32(len(out_buf)) / f32(_state.frame_rate)

    group_param_range: [NUM_GROUPS][Sound_Param_Kind][2]f32
    for &group, i in _state.groups {
        for &param, kind in group.sound_params {
            group_param_range[i][kind] = update_param(&param, global_delta_seconds)
        }
    }

    sound_loop: for sound_index in 1..<MAX_SOUNDS {
        sound := &_state.sounds[sound_index]

        switch intrinsics.atomic_load_explicit(&_state.sounds_state[sound_index], .Acquire) {
        case .Request_Free:
            _free_sound(sound_index)
            continue sound_loop
        case .Free:
            continue sound_loop

        case .Used:
        }

        if !sound.playing {
            continue
        }

        resource, resource_ok := _get_resource(sound.resource)
        assert(resource_ok)

        destroy := false

        // Wait before starting
        if sound.frame <= 0 {
            sound.frame += f64(global_delta_seconds) * f64(resource.frame_rate)
            continue
        }

        group_params := group_param_range[sound.group_index]

        params: [Sound_Param_Kind][2]f32
        for &param, kind in sound.params {
            params[kind] = update_param(&param, global_delta_seconds)
        }

        volume_range := params[.Volume] * group_params[.Volume]
        pitch_range := params[.Pitch] * group_params[.Pitch]
        doppler_factor := params[.Doppler_Factor] * group_params[.Doppler_Factor]
        attenuation_min := params[.Attenuation_Min] * group_params[.Attenuation_Min]
        attenuation_max := params[.Attenuation_Max] * group_params[.Attenuation_Max]

        pan_range := params[.Pan] + group_params[.Pan]
        lpf_range := params[.Lowpass]  + group_params[.Lowpass]
        hpf_range := params[.Highpass] + group_params[.Highpass]

        vel_range := [2][3]f32{
            sound.vel_prev,
            atomic_load_components_acquire(&sound.vel_curr),
        }
        sound.vel_prev = vel_range[1]

        if .Spatial in sound.flags {
            pos_range := [2][3]f32{
                sound.pos_prev,
                atomic_load_components_acquire(&sound.pos_curr),
            }
            sound.pos_prev = pos_range[1]

            diffs := [2][3]f32{
                pos_range[0] - listener_prev.pos,
                pos_range[1] - listener_pos,
            }

            // Distance Attenuation

            // Note: we're approximating the attenuation with linear equations.
            // This could be an issue for fast moving objects when they go right near the listener.
            dists := [2]f32{
                length(diffs[0]),
                length(diffs[1]),
            }

            attenuation := [2]f32{
                linear_attenuation(dists[0], {attenuation_min[0], attenuation_max[0]}),
                linear_attenuation(dists[1], {attenuation_min[1], attenuation_max[1]}),
            }

            volume_range *= attenuation

            // Doppler

            dirs := [2][3]f32{
                diffs[0] / max(0.0001, dists[0]),
                diffs[1] / max(0.0001, dists[1]),
            }

            doppler := [2]f32{
                (SPEED_OF_SOUND + dot(dirs[0], listener_prev.vel)) /
                (SPEED_OF_SOUND + dot(dirs[0], vel_range[0])),
                (SPEED_OF_SOUND + dot(dirs[1], listener_vel)) /
                (SPEED_OF_SOUND + dot(dirs[1], vel_range[1])),
            }

            doppler = {
                lerp(f32(1.0), doppler[0], doppler_factor[0]),
                lerp(f32(1.0), doppler[1], doppler_factor[1]),
            }

            pitch_range *= doppler

            // Spatial panning

            side_dots := [2]f32{
                dot(dirs[0], listener_prev.right),
                dot(dirs[1], listener_right),
            }

            side_dots = -side_dots

            pan_range = pan_range + side_dots * 0.8

            // Small spatial frequency response (hacky)
            // Above: HPF due to ear shape

            forw_dots := [2]f32{
                dot(dirs[0], listener_prev.forw),
                dot(dirs[1], listener_forw),
            }

            up_dots := [2]f32{
                dot(dirs[0], listener_prev_up),
                dot(dirs[1], listener_up),
            }

            LPF_BEHIND :: 0.45
            LPF_BELOW :: 0.35 // ground/body in the way
            HPF_ABOVE :: 0.04

            lpf_range += {
                max(-forw_dots[0], 0),
                max(-forw_dots[1], 0),
            } * LPF_BEHIND

            lpf_range += {
                max(-up_dots[0], 0),
                max(-up_dots[1], 0),
            } * LPF_BELOW

            hpf_range += {
                max(up_dots[0], 0),
                max(up_dots[1], 0),
            } * HPF_ABOVE
        }

        // Skip silent
        SILENCE_EPS :: 0.005
        if abs(volume_range[0]) < SILENCE_EPS && abs(volume_range[1]) < SILENCE_EPS {
            continue sound_loop
        }

        for &pan in pan_range {
            pan = clamp(pan, -1, 1)
        }

        delta_rate := f32(resource.frame_rate) / f32(frame_rate)

        end_time := sample_base_signal(
            out_buf = scratch,
            frame_bytes = resource.data,
            frame_num = resource.frame_num,
            format = resource.format,
            mono = .Mono in resource.flags,
            time = sound.frame,
            delta_range = pitch_range * delta_rate,
            loop = .Loop in sound.flags,
            frame_range = sound.frame_range,
        )

        sound.frame = end_time

        if .Loop not_in sound.flags && int(sound.frame) > int(sound.frame_range[1] - sound.frame_range[0]) {
            destroy = true
        }

        // Recursive filters
        // TODO: better filtering. Butterworth?
        // One-pole HPF and LPF
        // TODO: 2nd-order filtering?
        // Per-channel filtering?

        inv_frames := 1.0 / f32(len(out_buf))

        lpf_range = {
            clamp(lpf_range[0], 0, 0.995),
            clamp(lpf_range[1], 0, 0.995),
        }

        hpf_range = {
            clamp(hpf_range[0], 0, 1.0 - 1e-5),
            clamp(hpf_range[1], 0, 1.0 - 1e-5),
        }

        if
            lpf_range[0] > 1e-5 ||
            lpf_range[1] > 1e-5 ||
            hpf_range[0] > 1e-5 ||
            hpf_range[1] > 1e-5
        {
            lpf_prev := sound.lpf_prev
            hpf_prev := sound.hpf_prev

            lpf_range = 1 - lpf_range

            for &frame, i in scratch {
                block_t := f32(i) * inv_frames
                lpf_alpha := lerp(lpf_range[0], lpf_range[1], block_t)
                hpf_alpha := lerp(hpf_range[0], hpf_range[1], block_t)

                lpf_prev = lerp(lpf_prev, frame, lpf_alpha)
                hpf_prev = lerp(hpf_prev, frame, hpf_alpha)

                frame = lpf_prev - hpf_prev

                frame *= 1.0 / (1.0 - hpf_alpha) // HPF volume compensation
            }

            sound.lpf_prev = lpf_prev
            sound.hpf_prev = hpf_prev
        }

        // Finally add to output buffer

        for frame, i in scratch {
            block_t := f32(i) * inv_frames
            volume := lerp(volume_range[0], volume_range[1], block_t)
            pan := lerp(pan_range[0], pan_range[1], block_t)

            val := frame
            val *= volume

            // Pan/Balance:
            // -1 = hard left, L=1, R=0
            // 0 = center, L^2 + R^2 = 1
            // 1 = hard right, L=0, R=1
            //
            // https://www.desmos.com/calculator/ouck8jw1me

            pan_half := pan * 0.5
            val.x *= intrinsics.sqrt(0.5 + pan_half)
            val.y *= intrinsics.sqrt(0.5 - pan_half)

            out_buf[i] += val
        }

        if destroy {
            _free_sound(sound_index)
        }
    }

    // Final pass
    // Applies a limiter curve

    out_buf_simd := reinterpret_slice(#simd[8]f32, out_buf)
    for &vec in out_buf_simd {
        // FIXME
        // vec = fast_tanh_simd(vec)
    }

    return

    _free_sound :: proc(sound_index: int) {
        intrinsics.atomic_store(&_state.sounds_state[sound_index], .Free)
        base.spsc_push(&_state.sounds_free, Handle_Index(sound_index))
    }
}

// Approximation for tanh(x) in the range [-3, 3].
// Pade epproximant with C2 continuity.
fast_tanh :: proc(x: f32) -> f32 {
    if x < -3 {
        return -1
    }
    if x > 3 {
        return 1
    }
    xx := x * x
    return x * (27 + xx) / (27 + 9 * xx)
}

fast_tanh_simd :: proc(x: $T/#simd[$N]f32) -> T {
    x := x
    x = intrinsics.simd_clamp(x, -3, 3)
    xx := x * x
    return x * (27 + xx) / (27 + 9 * xx)
}



//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Signal
//

// Interpolated, Stereo/Mono
sample_base_signal :: proc(
    out_buf:        [][2]f32,
    frame_bytes:    [^]byte,
    frame_num:      u32,
    format:         Resource_Format,
    mono:           bool,
    time:           f64,
    delta_range:    [2]f32,
    loop:           bool,
    frame_range:    [2]u32,
) -> f64 {
    time := time

    assert((frame_range[1] - frame_range[0]) > 0)

    DELTA_EPS :: 0.0001
    delta_one :=
        abs(delta_range[0] - 1.0) < DELTA_EPS &&
        abs(delta_range[1] - 1.0) < DELTA_EPS

    switch format {
    case .Invalid, .WAV:
        assert(false)

    case .Raw_F32:
        if mono {
            samples := (cast([^]f32)frame_bytes)[:frame_num][frame_range[0] : frame_range[1]]
            if delta_one {
                time = _sample_signal_direct_mono_f32_copy(samples, out_buf, time, loop = loop)
            } else {
                time = _sample_signal_fallback(samples, out_buf, time, delta_range = delta_range, loop = loop)
            }
        } else {
            samples := (cast([^][2]f32)frame_bytes)[:frame_num][frame_range[0] : frame_range[1]]

            if delta_one {
                time = _sample_signal_direct_stereo_f32_copy(samples, out_buf, time, loop = loop)
            } else {
                time = _sample_signal_fallback(samples, out_buf, time, delta_range = delta_range, loop = loop)
            }
        }

    case .Raw_I16:
        if mono {
            samples := (cast([^]i16)frame_bytes)[:frame_num][frame_range[0] : frame_range[1]]
            time = _sample_signal_fallback(samples, out_buf, time, delta_range = delta_range, loop = loop)
        } else {
            samples := (cast([^][2]i16)frame_bytes)[:frame_num][frame_range[0] : frame_range[1]]
            time = _sample_signal_fallback(samples, out_buf, time, delta_range = delta_range, loop = loop)
        }

    case .Raw_U8:
        if mono {
            samples := (cast([^]u8)frame_bytes)[:frame_num][frame_range[0] : frame_range[1]]
            time = _sample_signal_fallback(samples, out_buf, time, delta_range = delta_range, loop = loop)
        } else {
            samples := (cast([^][2]u8)frame_bytes)[:frame_num][frame_range[0] : frame_range[1]]
            time = _sample_signal_fallback(samples, out_buf, time, delta_range = delta_range, loop = loop)
        }
    }

    return time
}

// TODO: accelerated method when sample rates match exactly and delta == 1
_sample_signal_fallback :: proc(
    frames:         []$T,
    out_buf:        [][2]f32,
    time:           f64,
    delta_range:    [2]f32,
    loop:           bool,
) -> f64 {
    time := time

    last_frame := uint(len(frames) - 1)
    inv_frames := 1.0 / f32(len(out_buf))

    for i in 0..<len(out_buf) {
        block_t := f32(i) * inv_frames

        index0 := uint(time)
        index1 := index0 + 1
        frame_t := f32(time - f64(index0))

        if loop {
            index0 %= uint(len(frames))
            index1 %= uint(len(frames))
        } else {
            index0 = min(index0, last_frame)
            index1 = min(index1, last_frame)
        }

        val0 := unpack_frame(frames[index0])
        val1 := unpack_frame(frames[index1])

        val := [2]f32{
            lerp(val0[0], val1[0], frame_t),
            lerp(val0[1], val1[1], frame_t),
        }

        out_buf[i] = val

        delta := lerp(delta_range[0], delta_range[1], block_t)
        time += f64(delta)
    }

    return time
}

// Pitch = 1
_sample_signal_direct_stereo_f32_copy :: proc(
    samples:    [][2]f32,
    out_buf:    [][2]f32,
    time:       f64,
    loop:       bool,
) -> f64 {
    time := time

    samples_offset := int(time)
    buf_offset := 0
    for buf_offset < len(out_buf) {
        if samples_offset >= len(samples) {
            if loop {
                samples_offset %= len(samples)
            } else {
                break
            }
        }

        buf_remaining := len(out_buf) - buf_offset
        samples_remaining := len(samples) - samples_offset

        num_frames := max(0, min(buf_remaining, samples_remaining))

        if num_frames > 0 {
            intrinsics.mem_copy_non_overlapping(
                raw_data(out_buf[buf_offset:]),
                raw_data(samples[samples_offset:]),
                size_of([2]f32) * num_frames,
            )
        }

        samples_offset += num_frames
        buf_offset += num_frames

    }

    // Fill tail with last sample, emulates clamped frame index
    last_sample := samples[len(samples) - 1]
    for ; buf_offset < len(out_buf); buf_offset += 1 {
        out_buf[buf_offset] = last_sample
    }

    return time + f64(len(out_buf))
}

// Pitch = 1
_sample_signal_direct_mono_f32_copy :: proc(
    samples:    []f32,
    out_buf:    [][2]f32,
    time:       f64,
    loop:       bool,
) -> f64 {
    time := time

    samples_offset := int(time)
    buf_offset := 0
    for buf_offset < len(out_buf) {
        if samples_offset >= len(samples) {
            if loop {
                samples_offset %= len(samples)
            } else {
                break
            }
        }

        buf_remaining := len(out_buf) - buf_offset
        samples_remaining := len(samples) - samples_offset

        num_frames := max(0, min(buf_remaining, samples_remaining))

        for sample, i in samples[samples_offset:][:num_frames] {
            out_buf[buf_offset + i] = sample
        }

        samples_offset += num_frames
        buf_offset += num_frames

    }

    // Fill tail with last sample, emulates clamped frame index
    last_sample := samples[len(samples) - 1]
    for ; buf_offset < len(out_buf); buf_offset += 1 {
        out_buf[buf_offset] = last_sample
    }

    return time + f64(len(out_buf))
}


unpack_frame :: proc {
    unpack_frame_mono_f32,
    unpack_frame_mono_i16,
    unpack_frame_mono_u8,
    unpack_frame_stereo_f32,
    unpack_frame_stereo_i16,
    unpack_frame_stereo_u8,
}

unpack_frame_mono_u8 :: proc(v: u8) -> [2]f32 {
    return (f32(v) - 128.0) * (1.0 / 255.0)
}

unpack_frame_mono_i16 :: proc(v: i16) -> [2]f32 {
    return f32(v) * (1.0 / 32768.0)
}

unpack_frame_mono_f32 :: proc(v: f32) -> [2]f32 {
    return v
}

unpack_frame_stereo_u8 :: proc(v: [2]u8) -> [2]f32 {
    return ({f32(v.x), f32(v.y)} - 128.0) * (1.0 / 255.0)
}

unpack_frame_stereo_i16 :: proc(v: [2]i16) -> [2]f32 {
    return {f32(v.x), f32(v.y)} * (1.0 / 32768.0)
}

unpack_frame_stereo_f32 :: proc(v: [2]f32) -> [2]f32 {
    return v
}


//////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// MARK: Util
//

atomic_load_components_acquire :: proc {
    atomic_load_components_acquire_single,
    atomic_load_components_acquire_vec,
}

atomic_load_components_acquire_single :: proc(v: ^$T) -> T where !intrinsics.type_is_array(T) {
    return intrinsics.atomic_load_explicit(v, .Acquire)
}

atomic_load_components_acquire_vec :: proc(v: ^$T/[$N]$V) -> (result: T) {
    for &res, i in result {
        res = intrinsics.atomic_load_explicit(&v[i], .Acquire)
    }
    return result
}

atomic_store_components_release_vec :: proc(dst: ^$T/[$N]$V, v: T) {
    for &res, i in dst {
        intrinsics.atomic_store_explicit(&dst[i], v[i], .Release)
    }
}

update_param :: proc(param: ^Param, delta: f32) -> (result: [2]f32) {
    target := intrinsics.atomic_load_explicit(&param.target, .Acquire)
    param_delta := intrinsics.atomic_load_explicit(&param.delta, .Acquire)

    result = {
        param.curr,
        move_towards_f32(param.curr, target, param_delta * delta),
    }

    param.curr = result[1]

    return result
}

// Result is in 0..1 range
// https://www.desmos.com/calculator/yzwr08ktae
linear_attenuation :: proc(x: f32, range: [2]f32) -> f32 {
    val := 1 - clamp((x - range[0]) / (range[1] - range[0]), 0, 1)
    return val // * val
}

@(require_results)
lerp :: proc "contextless" (a, b: $T, t: f32) -> T {
    return a * (1 - t) + b * t
}

@(require_results)
dot :: proc "contextless" (a, b: [3]f32) -> f32 {
    ab := a * b
    return ab.x + ab.y + ab.z
}

@(require_results)
cross :: proc "contextless" (a, b: [3]f32) -> (c: [3]f32) {
    return a.yzx*b.zxy - b.yzx*a.zxy
}

@(require_results)
length :: proc "contextless" (v: [3]f32) -> f32 {
    vv := v * v
    return intrinsics.sqrt(vv.x + vv.y + vv.z)
}

@(require_results)
normalize :: proc "contextless" (v: [3]f32) -> [3]f32 {
    l := length(v)
    if l <= 1e-6 {
        return 0
    }
    return v / l
}

move_towards :: proc {
    move_towards_f32,
    move_towards_vec3,
}

@(require_results)
move_towards_f32 :: proc "contextless" (val: f32, target: f32, delta: f32) -> f32 {
    diff := target - val
    if abs(diff) < delta {
        return target
    }
    return val + (diff > 0 ? delta : -delta)
}

@(require_results)
move_towards_vec3 :: proc "contextless" (val: [3]f32, target: [3]f32, delta: f32) -> [3]f32 {
    diff := target - val
    len2 := dot(diff, diff)
    if len2 < delta * delta || len2 < 0.001 {
        return target
    }
    dir := diff / intrinsics.sqrt(len2)
    return val + dir * delta
}


@(require_results)
reinterpret_slice :: proc "contextless" ($T: typeid, data: []$E, loc := #caller_location) -> []T {
    bytes := to_bytes(data)
    n := len(bytes) / size_of(T)
    assert_contextless(n * size_of(T) == len(bytes), loc = loc)
    return (cast([^]T)raw_data(bytes))[:n]
}

@(require_results)
reinterpret_bytes :: proc "contextless" ($T: typeid, bytes: []byte, loc := #caller_location) -> []T {
    n := len(bytes) / size_of(T)
    assert_contextless(n * size_of(T) == len(bytes), loc = loc)
    return ([^]T)(raw_data(bytes))[:n]
}

@(require_results)
to_bytes :: proc "contextless" (data: []$T) -> []byte {
    return (cast([^]byte)raw_data(data))[:size_of(T) * len(data)]
}

volume_linear_to_db :: proc(factor: f32) -> f32 {
    return 20 * math.log10_f32(factor)
}

volume_db_to_linear :: proc(gain: f32) -> f32 {
    return math.pow_f32(10, gain / 20.0)
}

// Returns frequency in Hz for a given midi note.
note_freq :: proc(#any_int midi_n: i32) -> f32 {
    return 440 * math.pow_f32(2, f32(midi_n - 69) * (1.0 / 12.0))
}

