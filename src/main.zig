const kernel = @import("kernel/kernel.zig");

pub fn main() !void {
    try kernel.boot();
}
