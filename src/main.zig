const std = @import("std");
const image_reader = @import("cpu/image_reader.zig");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    const path = args.next() orelse {
        std.debug.print("Please provide a path for an image\n", .{});
        std.process.exit(1);
    };

    try image_reader.read_image(path);
}
