const std = @import("std");
const Instruction = @import("instructions.zig").Instruction;
const utils = @import("../utils.zig");
const Reg = @import("registers.zig").Reg;

pub const ContextSaver = struct {
    const Self = @This();

    registers: Reg.RegSet,

    pub fn new() ContextSaver {
        var reg = Reg.get_set();
        reg[@intFromEnum(Reg.COND)] = @intFromEnum(utils.FLAG.ZRO);
        reg[@intFromEnum(Reg.PC)] = 0;
        return ContextSaver{ .registers = reg };
    }

    pub fn save(self: *Self) void {
        self.registers = Reg.get_set();
    }

    pub fn restore_context(self: *Self) void {
        for (self.registers, 0..) |r, i| {
            const reg: Reg = @enumFromInt(i);
            reg.set(r);
        }
    }

    pub fn set_reg(self: *Self, reg: Reg, val: Instruction) void {
        self.registers[@intFromEnum(reg)] = val;
    }
};
