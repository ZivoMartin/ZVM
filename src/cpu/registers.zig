const utils = @import("utils.zig");

pub const Reg = enum(u8) {
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

    var reg: [@typeInfo(Reg).@"enum".fields.len]u16 = undefined;

    pub fn set(self: Reg, val: u16) void {
        reg[@intFromEnum(self)] = val;
    }

    pub fn get(self: Reg) u16 {
        return reg[@intFromEnum(self)];
    }

    pub fn add(self: Reg, x: u16) void {
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
