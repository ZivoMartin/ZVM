const utils = @import("utils.zig");
const std = @import("std");
const Instruction = @import("instructions.zig").Instruction;

const ADDRESS_SIZE = 20;
const ADDRESS = u20;
const MEMORY_MAX: u64 = 1 << ADDRESS_SIZE;
var memory: [MEMORY_MAX]Instruction = undefined;
pub const PC_START = 0x3000;

pub fn read(i: ADDRESS) !Instruction {
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

pub fn write(i: ADDRESS, x: Instruction) void {
    memory[i] = x;
}

fn getProgramOrigin(_: std.fs.File) !ADDRESS {
    return 0;
}

pub fn inject_image(image_path: [:0]const u8) !void {
    const file = try std.fs.cwd().openFile(image_path, .{});
    defer file.close();
    const origin = try getProgramOrigin(file);
    var buffer: [4]u8 = undefined;
    var index = origin;
    while (true) : (index += 1) {
        const bytes_read = try file.read(&buffer);
        if (bytes_read < buffer.len or index >= MEMORY_MAX) break;
        memory[index] = std.mem.readInt(Instruction, &buffer, .big);
    }
}
