const std = @import("std");
const Process = @import("../cpu/process.zig").Process;
const shell = @import("../shell/shell.zig");
const Reg = @import("../cpu/registers.zig").Reg;
const memory = @import("../cpu/memory.zig");

pub fn boot() !void {
    var args = std.process.args();
    _ = args.skip();
    const path = args.next() orelse {
        try shell.run();
        return;
    };

    var process = try Process.new(try memory.get_process_mem_space());
    try process.setup_memory(path);

    while (process.running) {
        const syscall = try process.next_instruction();

        if (syscall != null) {
            try syscall.?.handle(&process);
        }
    }
}
