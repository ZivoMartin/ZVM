const Process = @import("../cpu/Process.zig").Process;
const Reg = @import("../cpu/registers.zig").Reg;
const stdout = @import("../utils.zig").stdout;
const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL_ttf.h");
});
const Shell = @import("../shell/shell.zig");
const Ch = @import("../sync_tools/Channel.zig");
const Distributer = @import("Distributer.zig").Distributer;

pub const Syscall = enum(u8) {
    Halt,
    WriteStdOut,
    GetC,

    fn halt(process: *Process) void {
        process.*.running = false;
    }

    fn write_stdout(shell_sender: ?*Shell.ShellSender, alloc: std.mem.Allocator, process: *Process) !void {
        if (shell_sender != null) {
            const addr = Reg.R1.get();
            const s = process.mem_read(@truncate(addr));
            try shell_sender.?.send(try Shell.ShellMessage.newStdout(alloc, s));
        }
    }

    pub fn handle(self: Syscall, dis: *Distributer, process: *Process) !void {
        switch (self) {
            .Halt => halt(process),
            .WriteStdOut => try write_stdout(dis.shell_sender, dis.alloc, process),
            .GetC => {},
        }
    }
};
