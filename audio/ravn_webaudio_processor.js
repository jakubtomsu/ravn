class RavnAudioWorkletProcessor extends AudioWorkletProcessor {
    constructor(params) {
        super();
        this.buffers = []; // Transferrables
        this.curr_buffer_offset = 0;
        this.phase = 0;

        this.port.onmessage = (event) => {
            if (event.data.type === 'queue_buffer') {
                this.buffers.push(event.data.data);
            }
        };
    }

    process(inputs, outputs, params) {
        if (outputs[0].length !== 2) {
            return true;
        }

        const left = outputs[0][0];
        const right = outputs[0][1];

        let offset = 0;

        while (offset < left.length) {
            if (this.buffers.length == 0) {
                // Enable when tweaking buffer latency.
                // Helpful for investigating choppy sound playback.
                // console.warn("WebAudio: BUFFER STARVATION!")
                left.fill(0, offset);
                right.fill(0, offset);
                break;
            }

            let buffer = this.buffers[0];
            let buffer_length = buffer.length / 2;

            let target_remaining = left.length - offset;
            let buffer_remaining = buffer_length - this.curr_buffer_offset;
            let remaining = Math.min(target_remaining, buffer_remaining);

            let buffer_left  = buffer.subarray(
                this.curr_buffer_offset,
                this.curr_buffer_offset + remaining);
            let buffer_right = buffer.subarray(
                this.curr_buffer_offset + buffer_length,
                this.curr_buffer_offset + buffer_length + remaining);

            left.set(buffer_left, offset);
            right.set(buffer_right, offset);

            offset += remaining;
            this.curr_buffer_offset += remaining;

            if (this.curr_buffer_offset >= buffer_length) {
                this.port.postMessage(
                    {type: 'return_buffer', data: buffer},
                    [buffer.buffer]);
                this.buffers.shift();
                this.curr_buffer_offset = 0;
            }
        }

        return true;
    }
}

registerProcessor("ravn-audio-processor", RavnAudioWorkletProcessor);