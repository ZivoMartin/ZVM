const std = @import("std");
const Process = @import("../cpu/Process.zig").Process;
const shell = @import("../shell/shell.zig");
const Reg = @import("../cpu/registers.zig").Reg;
const Memory = @import("../cpu/Memory.zig");
const Kernel = @import("kernel.zig").Kernel;

fn shell_boot() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    var kernel = try Kernel.new(arena.allocator());
    try shell.run(&kernel);
    try kernel.deinit();
}

fn testing_boot(path: [:0]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    var process = try Process.new(arena.allocator(), try Memory.get_process_mem_space());
    try process.setup_memory(path);

    while (process.running) {
        const syscall = try process.next_instruction();

        if (syscall != null) {
            try syscall.?.handle(process);
        }
    }
}

pub fn boot() !void {
    var args = std.process.args();
    _ = args.skip();
    const path = args.next() orelse {
        try shell_boot();
        return;
    };
    try testing_boot(path);
}
