"use strict";

// https://itch.io/t/2025776/experimental-sharedarraybuffer-support
// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/SharedArrayBuffer#security_requirements

(function() {
    const BUFFER_SAMPLES = 480;
    const FRAME_RATE = 48000;

    class RavenAudioInterface {
        constructor(mem) {
            this.mem = mem;
            this.audio_context = null;
            this.audio_node = null;
            this.buffer_pool = []; // Transferrables
            this.num_queued_buffers = 0;
        }

        async _async_init() {
            this.audio_context = new AudioContext({sampleRate: FRAME_RATE});

            console.log("Webaudio initializing...")

            try {
                await this.audio_context.audioWorklet.addModule("raven_webaudio_processor.js");
            } catch (e) {
                console.log("Failed to load audio worklet processor")
            }

            this.audio_node = new AudioWorkletNode(this.audio_context, "raven-audio-processor", {
                outputChannelCount: [2],
            });

            this.audio_node.connect(this.audio_context.destination);

            this.audio_node.port.onmessage = (event) => {
                if (event.data.type === 'return_buffer') {
                    this.buffer_pool.push(event.data.data);
                    this.num_queued_buffers -= 1;
                }
            }

            this.resume_audio = () => {
                if (this.audio_context.state === 'suspended') {
                    this.audio_context.resume();
                }
            }

            document.addEventListener('click', this.resume_audio);
            document.addEventListener('keydown', this.resume_audio);
            document.addEventListener('touchstart', this.resume_audio);

            console.log("Webaudio init done")
        }

        getInterface() {
            return {
                init: () => {
                    if (this.audio_context !== null) {
                        return;
                    }
                    this._async_init()
                },

                shutdown: () => {
                    if (this.resume_audio) {
                        document.removeEventListener('click', this.resume_audio);
                        document.removeEventListener('keydown', this.resume_audio);
                        document.removeEventListener('touchstart', this.resume_audio);
                    }

                    if (this.audio_node) {
                        this.audio_node.disconnect();
                    }

                    if (this.audio_context) {
                        this.audio_context.close();
                    }

                    this.audio_node = null;
                    this.audio_context = null;
                    this.resume_audio = null;
                    this.num_queued_buffers = 0;
                },

                push_buffer: (data_ptr) => {
                    if (this.audio_node == null || this.audio_context.state === 'suspended') {
                        return;
                    }

                    let samples = new Float32Array(this.mem.memory.buffer, data_ptr, BUFFER_SAMPLES * 2);

                    let buffer = this.buffer_pool.length > 0
                        ? this.buffer_pool.pop()
                        : new Float32Array(BUFFER_SAMPLES * 2);

                    buffer.set(samples);

                    this.audio_node.port.postMessage(
                        {type: 'queue_buffer', data: buffer},
                        [buffer.buffer]);
                    this.num_queued_buffers += 1;
                },

                get_num_queued_buffers: () => {
                    return this.num_queued_buffers;
                },
            }
        };
    }

    window.odin = window.odin || {};
    window.odin.RavenAudioInterface = RavenAudioInterface;
})();