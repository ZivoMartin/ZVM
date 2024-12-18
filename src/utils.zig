const std = @import("std");
const linux = std.os.linux;
pub const stdin = std.io.getStdIn();
pub const stdout = std.io.getStdOut();
const Instruction = @import("cpu/instructions.zig").Instruction;

pub fn write_u32_bytes(buffer: *[4]u8, x: u32) void {
    buffer.*[0] = @truncate(x >> 24);
    buffer.*[1] = @truncate(x >> 16 & 0xFF);
    buffer.*[2] = @truncate(x >> 8 & 0xFF);
    buffer.*[3] = @truncate(x & 0xFF);
}

pub fn u32_bytes(x: u32) [4]u8 {
    return .{
        @truncate(x >> 24),
        @truncate(x >> 16 & 0xFF),
        @truncate(x >> 8 & 0xFF),
        @truncate(x & 0xFF),
    };
}

pub fn read_u32(buff: [4]u8) u32 {
    return (@as(u32, buff[0]) << 24) |
        (@as(u32, buff[1]) << 16) |
        (@as(u32, buff[2]) << 8) |
        @as(u32, buff[3]);
}

pub fn sign_extend(num: Instruction, comptime og_bits: u8) Instruction {
    if (og_bits == 0) {
        return 0;
    }
    const shift = 32 - @as(Instruction, og_bits);
    return @bitCast(@as(i32, @bitCast(num << shift)) >> shift);
}

pub const FLAG = enum(u4) {
    POS = 1 << 0,
    ZRO = 1 << 1,
    NEG = 1 << 2,
};

test "sign extend" {
    try std.testing.expectEqual(0b0000_0000_0000_0000_0000_0000_0000_0000, sign_extend(0b1111_1111_1111_1111_1111_1111_1111_1111, 0));
    try std.testing.expectEqual(0b0000_0000_0000_0000_0000_0000_0000_0000, sign_extend(0b1000_0000_0000_0000_1000_0000_0000_0000, 1));
    try std.testing.expectEqual(0b1111_1111_1111_1111_1111_1111_1111_1111, sign_extend(0b0000_0000_0000_0000_0000_0000_0000_0001, 1));
    try std.testing.expectEqual(0b0000_0000_0000_0000_0000_0000_0011_1111, sign_extend(0b1111_1111_1111_1111_1111_1111_1011_1111, 7));
    try std.testing.expectEqual(0b1111_1111_1111_1111_1111_1111_1101_0101, sign_extend(0b0000_0000_0000_0000_0000_0000_0101_0101, 7));
    try std.testing.expectEqual(0b0000_0000_0000_0000_0000_0000_0000_0000, sign_extend(0b1111_1111_1111_1111_1111_0000_0000_0000, 12));
    try std.testing.expectEqual(0b1111_1111_1111_1111_1111_1111_0000_1111, sign_extend(0b0000_0000_0000_0000_0000_1111_0000_1111, 12));
    try std.testing.expectEqual(0b0000_0000_0000_0000_0010_0000_0000_0000, sign_extend(0b0000_0000_0000_0000_0010_0000_0000_0000, 15));
    try std.testing.expectEqual(0b1111_1111_1111_1111_1100_0000_0000_0000, sign_extend(0b0000_0000_0000_0000_0100_0000_0000_0000, 15));
}

test "u32_bytes_cast" {
    const x = 100;
    const buff = u32_bytes(x);
    try std.testing.expectEqual(read_u32(buff), x);
}
