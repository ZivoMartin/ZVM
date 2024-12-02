const utils = @import("utils.zig");
const registers = @import("registers.zig");
const memory = @import("memory.zig");
const traps = @import("traps.zig");

const Reg = registers.Reg;

pub const OP = enum(u8) {
    BR,
    ADD,
    LD,
    ST,
    JSR,
    AND,
    LDR,
    STR,
    RTI,
    NOT,
    LDI,
    STI,
    JMP,
    RES,
    LEA,
    TRAP,

    pub fn handle_instruction(self: OP, instr: u16) !void {
        switch (self) {
            .BR => {
                const cond_flag = (instr >> 9) & 0x7;
                if ((cond_flag & Reg.COND.get()) != 0) {
                    const pc_offset = utils.sign_extend(instr & 0x1FF, 9);
                    Reg.PC.add(pc_offset);
                }
            },
            .ADD => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const imm_flag = (instr >> 5) & 0x1;
                if (imm_flag != 0) {
                    const imm5 = utils.sign_extend(instr & 0x1F, 5);
                    r0.set(r1.get() +% imm5);
                } else {
                    const r2: Reg = @enumFromInt(instr & 0x7);
                    r0.set(r1.get() +% r2.get());
                }
                r0.update_flags();
            },
            .LD => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = utils.sign_extend(instr & 0x1FF, 9);
                r0.set(try memory.read(Reg.PC.get() +% pc_offset));
                r0.update_flags();
            },
            .ST => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = utils.sign_extend(instr & 0x1FF, 9);
                memory.write(Reg.PC.get() +% pc_offset, r0.get());
            },
            .JSR => {
                const long_flag = (instr >> 11) & 0x1;
                Reg.R7.set(Reg.PC.get());
                if (long_flag != 0) {
                    const long_pc_offset = utils.sign_extend(instr & 0x7FF, 11);
                    Reg.PC.add(long_pc_offset);
                } else {
                    const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                    Reg.PC.set(r1.get());
                }
            },
            .AND => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const imm_flag = (instr >> 5) & 0x1;
                if (imm_flag != 0) {
                    const imm5 = utils.sign_extend(instr & 0x1F, 5);
                    r0.set(r1.get() & imm5);
                } else {
                    const r2: Reg = @enumFromInt(instr & 0x7);
                    r0.set(r1.get() & r2.get());
                }
                r0.update_flags();
            },
            .LDR => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const offset = utils.sign_extend(instr & 0x3F, 6);
                r0.set(try memory.read(r1.get() +% offset));
                r0.update_flags();
            },
            .STR => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const offset = utils.sign_extend((instr & 0x3F), 6);
                memory.write(r1.get() +% offset, r0.get());
            },
            .RTI => {},
            .NOT => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                r0.set(~r1.get());
                r0.update_flags();
            },
            .LDI => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = utils.sign_extend(instr & 0x1FF, 9);
                r0.set(try memory.read(try memory.read(Reg.PC.get() +% pc_offset)));
                r0.update_flags();
            },
            .STI => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = utils.sign_extend(instr & 0x1FF, 9);
                memory.write(try memory.read(Reg.PC.get() +% pc_offset), r0.get());
            },
            .JMP => {
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                Reg.PC.set(r1.get());
            },
            .RES => {},
            .LEA => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = utils.sign_extend(instr & 0x1FF, 9);
                r0.set(Reg.PC.get() +% pc_offset);
                r0.update_flags();
            },
            .TRAP => {
                Reg.R7.set(Reg.PC.get());
                const trap: traps.TR = @enumFromInt(instr & 0xFF);
                try trap.process();
            },
        }
    }
};
