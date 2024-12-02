const std = @import("std");
const image_reader = @import("cpu/image_reader.zig");
const shell = @import("shell/shell.zig");

pub fn main() !void {
    var args = std.process.args();
    _ = args.skip();
    const path = args.next() orelse {
        try shell.run();
        return;
    };

    try image_reader.read_image(path);
}
