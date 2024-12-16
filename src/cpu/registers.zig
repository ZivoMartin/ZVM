const utils = @import("utils.zig");
const Instruction = @import("instructions.zig").Instruction;
const InstructionSigned = @import("instructions.zig").InstructionSigned;
const std = @import("std");

pub const Reg = enum(u4) {
    R0 = 0,
    R1,
    R2,
    R3,
    R4,
    R5,
    R6,
    R7,
    PC,
    COND,

    pub const RegSet: type = [@typeInfo(Reg).@"enum".fields.len]Instruction;

    var reg: RegSet = undefined;

    pub fn get_set() RegSet {
        return reg;
    }

    pub fn set(self: Reg, val: Instruction) void {
        reg[@intFromEnum(self)] = val;
    }

    pub fn get(self: Reg) Instruction {
        return reg[@intFromEnum(self)];
    }

    pub fn set_signed(self: Reg, val: InstructionSigned) void {
        reg[@intFromEnum(self)] = @bitCast(val);
    }

    pub fn get_signed(self: Reg) InstructionSigned {
        return @bitCast(reg[@intFromEnum(self)]);
    }

    pub fn add(self: Reg, x: Instruction) void {
        self.set(self.get() +% x);
    }

    pub fn update_flags(self: Reg) void {
        const val: InstructionSigned = @bitCast(self.get());
        if (val == 0) {
            set_flag_zero();
        } else if (val < 0) {
            set_flag_neg();
        } else {
            set_flag_pos();
        }
    }

    pub fn set_flag_zero() void {
        Reg.COND.set(@intFromEnum(utils.FLAG.ZRO));
    }
    pub fn set_flag_pos() void {
        Reg.COND.set(@intFromEnum(utils.FLAG.POS));
    }
    pub fn set_flag_neg() void {
        Reg.COND.set(@intFromEnum(utils.FLAG.NEG));
    }

    pub fn trace() void {
        for (reg) |r| std.debug.print("{} ", .{r});
        std.debug.print("\n", .{});
    }

    pub fn clear() void {
        for (0..reg.len) |i| reg[i] = 0;
    }
};
