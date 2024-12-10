const std = @import("std");
const linux = std.os.linux;
pub const stdin = std.io.getStdIn();
pub const stdout = std.io.getStdOut();
const Instruction = @import("instructions.zig").Instruction;

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
