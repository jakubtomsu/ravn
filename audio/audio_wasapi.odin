#+build windows
package ravn_audio

import "core:log"
import "../base"
import "base:intrinsics"
import "core:sys/windows"
import "vendor:windows/wasapi"

when BACKEND == BACKEND_WASAPI {
    _State :: struct {
        audio_client:       ^wasapi.IAudioClient,
        render_client:      ^wasapi.IAudioRenderClient,
        thread:             windows.HANDLE,
        buffer_event:       windows.HANDLE,
        buffer_frame_num:   u32,
    }

    @(require_results)
    _init :: proc() -> bool {
        _wasapi_check(windows.CoInitializeEx(nil, .MULTITHREADED))

        enumerator: ^wasapi.IMMDeviceEnumerator
        _wasapi_check(windows.CoCreateInstance(
            wasapi.CLSID_MMDeviceEnumerator,
            nil,
            windows.CLSCTX_ALL,
            wasapi.IID_IMMDeviceEnumerator,
            (^rawptr)(&enumerator),
        )) or_return

        defer {
            enumerator->Release()
            enumerator = nil
        }

        device: ^wasapi.IMMDevice
        _wasapi_check(enumerator->GetDefaultAudioEndpoint(.Render, .Console, &device)) or_return
        _wasapi_check(device->Activate(wasapi.IID_IAudioClient, windows.CLSCTX_ALL, nil, cast(^rawptr)&_state.audio_client)) or_return

        defer {
            device->Release()
            device = nil
        }

        device_format: ^wasapi.WAVEFORMATEXTENSIBLE
        _wasapi_check(_state.audio_client->GetMixFormat(cast(^^wasapi.WAVEFORMATEX)&device_format)) or_return
        assert(device_format.Format.wFormatTag == .EXTENSIBLE)
        defer windows.CoTaskMemFree(device_format)

        log.info(
            "WASAPI Device format: samplerate: %i, channels: %v (%i), f32: %v",
            device_format.Format.nSamplesPerSec,
            device_format.dwChannelMask,
            device_format.Format.nChannels,
            device_format.Samples.wValidBitsPerSample == 32 &&
                device_format.SubFormat == wasapi.KSDATAFORMAT_SUBTYPE_IEEE_FLOAT,
        )

        format := (cast(^wasapi.WAVEFORMATEXTENSIBLE)device_format)^
        format.Samples.wValidBitsPerSample = 32
        format.Format.nChannels = 2
        format.dwChannelMask = {.FRONT_LEFT, .FRONT_RIGHT}
        format.SubFormat = wasapi.KSDATAFORMAT_SUBTYPE_IEEE_FLOAT

        _state.frame_rate = u32(format.Format.nSamplesPerSec)

        BUFFER_MS :: 1
        buffer_duration: wasapi.REFERENCE_TIME = 10 * 1000 * BUFFER_MS

        client_flags: u32
        if !SINGLE_THREAD {
            client_flags |= u32(wasapi.AUDCLNT_FLAG.STREAM_EVENTCALLBACK)
        }

        closest: ^wasapi.WAVEFORMATEX
        if _state.audio_client->IsFormatSupported(.SHARED, cast(^wasapi.WAVEFORMATEX)&format, &closest) != windows.S_OK {
            log.error("WASAPI: stereo f32 not supported.")
            return false
        }

        _wasapi_check(_state.audio_client->Initialize(
            .SHARED,
            client_flags,
            buffer_duration,
            0,
            cast(^wasapi.WAVEFORMATEX)&format,
            nil,
        )) or_return

        if !SINGLE_THREAD {
            _state.buffer_event = windows.CreateEventW(nil, false, false, nil)
            _wasapi_check(_state.audio_client->SetEventHandle(_state.buffer_event))
        }

        _wasapi_check(_state.audio_client->GetService(wasapi.IID_IAudioRenderClient, cast(^rawptr)&_state.render_client)) or_return

        _wasapi_check(_state.audio_client->GetBufferSize(&_state.buffer_frame_num)) or_return
        _wasapi_check(_state.audio_client->Start()) or_return

        if !SINGLE_THREAD {
            _state.thread = windows.CreateThread(
                lpThreadAttributes    = nil,
                dwStackSize           = 0,
                lpStartAddress        = _wasapi_thread_routine,
                lpParameter           = nil,
                dwCreationFlags       = 0,
                lpThreadId            = nil,
            )

            if _state.thread == nil {
                log.error("Failed to create thread.")
                return false
            }

            windows.SetThreadDescription(_state.thread, "Audio Thread")
            windows.SetThreadPriority(_state.thread, windows.REALTIME_PRIORITY_CLASS)
        }

        return true
    }

    _shutdown :: proc() {
        assert(_state.audio_client != nil)
        assert(_state.render_client != nil)
        _state.audio_client->Stop()
        windows.WaitForSingleObject(_state.thread, 2000)
        windows.CloseHandle(_state.thread)
        _state.render_client->Release();
        _state.audio_client->Release();
        windows.CloseHandle(_state.buffer_event)
        windows.CoUninitialize()
    }

    _render :: proc() {
        if SINGLE_THREAD {
            _wasapi_render_buffer()
        }
    }

    _wasapi_render_buffer :: proc() {
        padding: u32
        if !_wasapi_check(_state.audio_client->GetCurrentPadding(&padding)) {
            return
        }

        frames_available := _state.buffer_frame_num - padding

        if frames_available == 0 {
            return
        }

        data_ptr: [^]byte
        if !_wasapi_check(_state.render_client->GetBuffer(frames_available, &data_ptr)) {
            return
        }

        frame_buf := (cast([^][2]f32)data_ptr)[:frames_available]
        intrinsics.mem_zero(raw_data(frame_buf), len(frame_buf) * size_of([2]f32))

        mixer_proc := intrinsics.atomic_load(&_state.master_mixer_proc)
        if mixer_proc != nil {
            mixer_proc(frame_buf, frame_rate = int(_state.frame_rate))
        }

        _wasapi_check(_state.render_client->ReleaseBuffer(frames_available, 0))
    }

    _wasapi_thread_routine :: proc "system" (_: rawptr) -> windows.DWORD {
        context = _state.init_context

        phase: f32

        for _state.running {
            assert(_state != nil)

            wait_res := windows.WaitForSingleObject(_state.buffer_event, 1000)
            if wait_res == windows.WAIT_OBJECT_0 {
                _wasapi_render_buffer()
            }
        }

        return 0
    }

    _wasapi_check :: proc(hr: windows.HRESULT, expr := #caller_expression, loc := #caller_location) -> bool {
        if !windows.SUCCEEDED(hr) {
            log.errorf("WASAPI Error: %v (%x)", transmute(wasapi.Result)hr, transmute(u32)hr, location = loc)
            return false
        }
        return true
    }
}