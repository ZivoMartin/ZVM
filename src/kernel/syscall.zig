const Process = @import("../cpu/Process.zig").Process;
const Reg = @import("../cpu/registers.zig").Reg;
const stdout = @import("../cpu/utils.zig").stdout;
const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL_ttf.h");
});

pub const Syscall = enum(u8) {
    Halt,
    WriteStdOut,
    GetC,
    InitGraphicInterface,
    OpenWindow,

    fn halt(process: *Process) void {
        process.*.running = false;
    }

    fn write_stdout(process: *Process) !void {
        var addr = Reg.R1.get();
        const writer = stdout.writer();
        while (true) : (addr += 1) {
            const c = process.read(@truncate(addr));
            if (c == 0) {
                break;
            }
            try writer.writeByte(c);
        }
    }

    fn init_graphic_interface(process: *Process) void {
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
            process.put_error("ERROR: Failed to init SDL\n");
        }
    }

    fn open_window(process: *Process) void {
        const title = process.stack_pop() catch {
            process.put_error("Failed to pop the title");
            return;
        };
        const height = process.stack_pop() catch {
            process.put_error("Failed to pop the height");
            return;
        };
        const width = process.stack_pop() catch {
            process.put_error("Failed to pop the width");
            return;
        };

        const window = sdl.SDL_CreateWindow(@ptrCast(process.mem_read(@truncate(title))), sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, @intCast(width), @intCast(height), sdl.SDL_WINDOW_RESIZABLE) orelse {
            process.put_error("Failed to create window");
            return;
        };

        const renderer = sdl.SDL_CreateRenderer(window, -1, 0) orelse {
            process.put_error("Unable to create renderer");
            return;
        };

        Reg.R0.set(@truncate(@intFromPtr(window)));
        Reg.R1.set(@truncate(@intFromPtr(renderer)));
    }

    pub fn handle(self: Syscall, process: *Process) !void {
        switch (self) {
            .Halt => halt(process),
            .WriteStdOut => try write_stdout(process),
            .GetC => {},
            .InitGraphicInterface => init_graphic_interface(process),
            .OpenWindow => open_window(process),
        }
    }
};
