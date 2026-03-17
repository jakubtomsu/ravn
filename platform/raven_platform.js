"use strict";

(function() {
    // TODO: get the canvas in the constructor instead of hardcoding it in the platform code?
    class RavenPlatformInterface {
        constructor(mem) {
            this.mem = mem;
        }

        getInterface() {
            return {
                init: (canvas_name_ptr, canvas_name_len) => {
                    const name = this.mem.loadString(canvas_name_ptr, canvas_name_len);
                    const canvas = document.querySelector(name);

                    // Disable the menu on the canvas specifically
                    canvas.addEventListener('contextmenu', (event) => {
                        event.preventDefault();
                    });
                },

                set_pointer_lock: (canvas_name_ptr, canvas_name_len, lock) => {
                    const name = this.mem.loadString(canvas_name_ptr, canvas_name_len);
                    const canvas = document.querySelector(name);

                    if (!canvas) {
                        console.error(`Raven set_pointer_lock: Canvas "${name}" not found.`);
                        return;
                    }

                    if (lock) {
                        canvas.requestPointerLock({
                            unadjustedMovement: true, // raw, no acceleration
                        });
                    } else {
                        if (document.pointerLockElement === canvas) {
                            document.exitPointerLock();
                        }
                    }
                },

                get_pointer_lock: (canvas_name_ptr, canvas_name_len) => {
                    const name = this.mem.loadString(canvas_name_ptr, canvas_name_len);
                    const canvas = document.querySelector(name);
                    return document.pointerLockElement === canvas;
                }
            }
        };
    }

    window.odin = window.odin || {};
    window.odin.RavenPlatformInterface = RavenPlatformInterface;
})();