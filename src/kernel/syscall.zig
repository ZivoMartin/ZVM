const Process = @import("../cpu/Process.zig").Process;
const Reg = @import("../cpu/registers.zig").Reg;
const stdout = @import("../cpu/utils.zig").stdout;
const std = @import("std");

pub const Syscall = enum(u8) {
    Halt,
    WriteStdOut,

    fn halt(process: *Process) void {
        process.*.running = false;
    }

    fn write_stdout(process: *Process) !void {
        var addr = Reg.R1.get();
        std.debug.print("{}\n", .{addr});
        const writer = stdout.writer();
        while (true) : (addr += 1) {
            const c = try process.read(@truncate(addr));
            if (c == 0) {
                break;
            }
            try writer.writeByte(c);
        }
    }

    pub fn handle(self: Syscall, process: *Process) !void {
        switch (self) {
            .Halt => halt(process),
            .WriteStdOut => try write_stdout(process),
        }
    }
};
