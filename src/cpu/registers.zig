const utils = @import("utils.zig");
const Instruction = @import("instructions.zig").Instruction;
const InstructionSigned = @import("instructions.zig").InstructionSigned;

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

    var reg: [@typeInfo(Reg).@"enum".fields.len]Instruction = undefined;

    pub fn clear() void {
        for (0..reg.len) |i| reg[i] = 0;
        Reg.COND.set(@intFromEnum(utils.FLAG.ZRO));
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
        const val = self.get();
        if (val == 0) {
            Reg.COND.set(@intFromEnum(utils.FLAG.ZRO));
        } else if (val >> 15 == 1) {
            Reg.COND.set(@intFromEnum(utils.FLAG.NEG));
        } else {
            Reg.COND.set(@intFromEnum(utils.FLAG.POS));
        }
    }
};
