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

pub fn boot() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // defer arena.deinit();
    var kernel = try Kernel.new(arena.allocator());
    try shell.run(&kernel);
    try kernel.deinit();
}
