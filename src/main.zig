const booter = @import("kernel/booter.zig");

pub fn main() !void {
    try booter.boot();
}
