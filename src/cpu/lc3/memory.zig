const utils = @import("utils.zig");
const std = @import("std");

const MEMORY_MAX: u64 = 1 << 16;
var memory: [MEMORY_MAX]u16 = undefined;
pub const PC_START = 0x3000;

pub fn read(i: u16) !u16 {
    if (i == @intFromEnum(utils.MR.KBSR)) {
        if (utils.check_key()) {
            memory[@intFromEnum(utils.MR.KBSR)] = 1 << 15;
            memory[@intFromEnum(utils.MR.KBDR)] = std.io.getStdIn().reader().readByte() catch memory[@intFromEnum(utils.MR.KBDR)];
        } else {
            memory[@intFromEnum(utils.MR.KBSR)] = 0;
        }
    }
    return memory[i];
}

pub fn write(i: u16, x: u16) void {
    memory[i] = x;
}

fn getProgramOrigin(file: std.fs.File) !u16 {
    var buffer: [2]u8 = undefined;
    const bytes_read = try file.read(&buffer);
    if (bytes_read < buffer.len) {
        return error.InsufficientData;
    }
    return std.mem.readInt(u16, &buffer, .big);
}

pub fn inject_image(image_path: [:0]const u8) !void {
    const file = try std.fs.cwd().openFile(image_path, .{});
    defer file.close();
    const origin = try getProgramOrigin(file);
    var buffer: [2]u8 = undefined;
    var index = origin;
    while (true) : (index += 1) {
        const bytes_read = try file.read(&buffer);
        if (bytes_read < buffer.len or index >= MEMORY_MAX) break;
        memory[index] = std.mem.readInt(u16, &buffer, .big);
    }
}
