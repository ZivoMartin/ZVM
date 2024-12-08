const utils = @import("utils.zig");
const registers = @import("registers.zig");
const memory = @import("memory.zig");
const traps = @import("traps.zig");
const std = @import("std");

pub const Instruction: type = u32;
pub const InstructionSigned: type = i32;

const Reg = registers.Reg;

pub const JUMP_CODE = enum(u3) { JMP = 0, JE, JH, JL, JLE, JHE };

pub const OP = enum(u5) {
    ADD = 0, // Add two values (OK)
    MUL, // Multiply two values
    SUB, // Sub two values
    DIV, // Divide two values
    MOD, // Mod of two values
    NEG, // Put the negation of a first register in a memory spot
    SHL, // Shift left for bitwise operations
    SHR, // Shift right for bitwise operations
    AND, // Perform binary and over two values
    OR, // Perform binary or over two values
    XOR, // Perform binary xor over two values
    NOT, // Perform binary not over a values
    JMP, // Jmp to an address of the code, conatins a jump code indicates the kind of jump
    INT, // Provoc an interruption
    PUSH, // Push a value on the stack, support pushf and pushr
    POP, // Pop a value of the stack, support popf and popr
    RET, // Pop a value of the stack and perform jump
    CALL, // Push the stack pointer and jmp
    MOV, // Mov a value in a register or a memory zone
    READ, // Read a value in the memory it in a register
    WRITE, // Write a value in the memory
    CMP, // Compare two values, actualise the condition flags
    CLEAR, // Set all the registers at 0
    HALT, // Stop the program
    TRACE, // Print the current state of registers/memory (helpful for debugging in a VM).
    DUP, // Duplicate the top value on the stack.
    SWAP, // Swap the top two values on the stack.

    const InstructionProcessingError = error{};

    const instr_handlers: [@typeInfo(OP).@"enum".fields.len]*const fn (Instruction) InstructionProcessingError!void = .{
        &add,
        &mul,
        &sub,
        &div,
        &mod,
        &neg,
        &shl,
        &shr,
        &_and,
        &_or,
        &xor,
        &not,
        &jmp,
        &int,
        &push,
        &pop,
        &ret,
        &call,
        &mov,
        &read,
        &write,
        &cmp,
        &clear,
        &halt,
        &trace,
        &dup,
        &swap,
    };

    pub fn handle_instruction(self: OP, instr: Instruction) !void {
        const op = @as(usize, @intFromEnum(self));
        try instr_handlers[op](instr);
    }

    const ArithmeticOperation = struct { dest: Reg, v1: Instruction, v2: Instruction };

    fn get_immediate_value(instr: Instruction) Instruction {
        return utils.sign_extend(instr & 0x1FFFFF, 20);
    }

    fn get_r0(instr: Instruction) Reg {
        return @enumFromInt((instr >> 24) & 0x7);
    }

    fn get_r1(instr: Instruction) Reg {
        return @enumFromInt((instr >> 21) & 0x7);
    }

    fn get_r2(instr: Instruction) Reg {
        return @enumFromInt(instr & 0x7);
    }

    pub fn get_op_values(instr: Instruction) ArithmeticOperation {
        const r0 = get_r0(instr);
        const r1 = get_r1(instr);
        const imm_flag = (instr >> 20) & 0x1;
        var res = ArithmeticOperation{ .dest = r0, .v1 = r1.get(), .v2 = 0 };
        if (imm_flag != 0) {
            res.v2 = get_immediate_value(instr);
        } else {
            res.v2 = get_r2(instr).get();
        }
        return res;
    }

    fn add(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 +% operation.v2);
        operation.dest.update_flags();
    }

    fn mul(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 *% operation.v2);
        operation.dest.update_flags();
    }

    fn sub(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 -% operation.v2);
        operation.dest.update_flags();
    }

    fn div(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 / operation.v2);
        operation.dest.update_flags();
    }

    fn mod(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 % operation.v2);
        operation.dest.update_flags();
    }

    fn shl(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 << @truncate(operation.v2));
        operation.dest.update_flags();
    }

    fn shr(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 >> @truncate(operation.v2));
        operation.dest.update_flags();
    }

    fn _or(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 | operation.v2);
        operation.dest.update_flags();
    }

    fn xor(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 ^ operation.v2);
        operation.dest.update_flags();
    }

    fn _and(instr: Instruction) !void {
        const operation = get_op_values(instr);
        operation.dest.set(operation.v1 & operation.v2);
        operation.dest.update_flags();
    }

    fn not(instr: Instruction) !void {
        const r0 = get_r0(instr);
        const r1 = get_r1(instr);
        r0.set(~r1.get());
        r0.update_flags();
    }

    fn neg(instr: Instruction) !void {
        const r0 = get_r0(instr);
        const r1 = get_r1(instr);
        const val: i32 = @bitCast(r1.get());
        r0.set(@bitCast(-val));
    }

    fn jmp(instr: Instruction) !void {
        const jcode: JUMP_CODE = @enumFromInt((instr >> 24) & 0x7);
        const addr = if ((instr >> 24) & 1 != 0) get_immediate_value(instr) else get_r2(instr).get();
        const cond = Reg.COND.get();
        switch (jcode) {
            .JMP => {
                Reg.PC.set(addr);
            },
            .JE => {
                if (cond == @intFromEnum(utils.FLAG.ZRO)) {
                    Reg.PC.set(addr);
                }
            },
            .JH => {
                if (cond == @intFromEnum(utils.FLAG.POS)) {
                    Reg.PC.set(addr);
                }
            },
            .JL => {
                if (cond == @intFromEnum(utils.FLAG.NEG)) {
                    Reg.PC.set(addr);
                }
            },
            .JHE => {
                if (cond == @intFromEnum(utils.FLAG.POS) or cond == @intFromEnum(utils.FLAG.ZRO)) {
                    Reg.PC.set(addr);
                }
            },
            .JLE => {
                if (cond == @intFromEnum(utils.FLAG.NEG) or cond == @intFromEnum(utils.FLAG.ZRO)) {
                    Reg.PC.set(addr);
                }
            },
        }
    }

    fn cmp(_: Instruction) !void {}

    fn ret(_: Instruction) !void {}
    fn call(_: Instruction) !void {}
    fn mov(_: Instruction) !void {}
    fn read(_: Instruction) !void {}
    fn write(_: Instruction) !void {}
    fn clear(_: Instruction) !void {}
    fn trace(_: Instruction) !void {}
    fn dup(_: Instruction) !void {}
    fn swap(_: Instruction) !void {}

    fn push(_: Instruction) !void {}
    fn pop(_: Instruction) !void {}

    fn halt(_: Instruction) !void {}
    fn int(_: Instruction) !void {}
};

test "add" {
    Reg.R0.set(5);
    Reg.R1.set(1);
    Reg.R2.set(2);

    // R0 = R1 + R2
    try OP.add(0b00000_000_001_0_00000000000000000_010);
    try std.testing.expect(Reg.R0.get() == 3);

    // R0 = R1 + 266242
    try OP.add(0b00000_000_001_1_01000001000000000010);
    try std.testing.expect(Reg.R0.get() == 266243);

    // R0 = R1 + 4294447106
    try OP.add(0b00000_000_001_1_10000001000000000010);
    try std.testing.expect(Reg.R0.get() == 4294447107);

    Reg.clear();
}

test "mul" {
    Reg.R0.set(0);
    Reg.R1.set(3);
    Reg.R2.set(4);

    // R0 = R1 * R2
    try OP.mul(0b00000_000_001_0_00000000000000000_010);
    try std.testing.expect(Reg.R0.get() == 12);

    // R0 = R1 * 5
    try OP.mul(0b00000_000_001_1_00000000000000000101);
    try std.testing.expect(Reg.R0.get() == 15);

    Reg.clear();
}

test "div" {
    Reg.R0.set(0);
    Reg.R1.set(20);
    Reg.R2.set(4);

    // R0 = R1 / R2
    try OP.div(0b00000_000_001_0_00000000000000000_010);
    try std.testing.expect(Reg.R0.get() == 5);

    // R0 = R1 / 3
    try OP.div(0b00000_000_001_1_00000000000000000011);
    try std.testing.expect(Reg.R0.get() == 6);

    Reg.clear();
}

test "mod" {
    Reg.R0.set(0);
    Reg.R1.set(20);
    Reg.R2.set(6);

    // R0 = R1 % R2
    try OP.mod(0b00000_000_001_0_00000000000000000_010);
    try std.testing.expect(Reg.R0.get() == 2);

    // R0 = R1 % 4
    try OP.mod(0b00000_000_001_1_00000000000000000100);
    try std.testing.expect(Reg.R0.get() == 0);

    Reg.clear();
}

test "sub" {
    Reg.R0.set(0);
    Reg.R1.set(15);
    Reg.R2.set(5);

    // R0 = R1 - R2
    try OP.sub(0b00000_000_001_0_00000000000000000_010);
    try std.testing.expect(Reg.R0.get() == 10);

    // R0 = R1 - 3
    try OP.sub(0b00000_000_001_1_00000000000000000011);
    try std.testing.expect(Reg.R0.get() == 12);

    Reg.clear();
}

test "shiftleft" {
    Reg.R0.set(0);
    Reg.R1.set(2);

    // R0 = R1 << 2
    try OP.shl(0b00000_000_001_1_00000000000000000010);
    try std.testing.expect(Reg.R0.get() == 8);

    Reg.clear();
}

test "shiftright" {
    Reg.R0.set(0);
    Reg.R1.set(16);

    // R0 = R1 >> 2
    try OP.shr(0b00000_000_001_1_00000000000000000010);
    try std.testing.expect(Reg.R0.get() == 4);

    Reg.clear();
}

test "binary or" {
    Reg.R0.set(0);
    Reg.R1.set(0b1010);
    Reg.R2.set(0b0101);

    // R0 = R1 | R2
    try OP._or(0b00000_000_001_0_00000000000000000_010);
    try std.testing.expect(Reg.R0.get() == 0b1111);

    Reg.clear();
}

test "binary and" {
    Reg.R0.set(0);
    Reg.R1.set(0b1010);
    Reg.R2.set(0b1100);

    // R0 = R1 & R2
    try OP._and(0b00000_000_001_0_00000000000000000_010);
    try std.testing.expect(Reg.R0.get() == 0b1000);

    Reg.clear();
}

test "binary xor" {
    Reg.R0.set(0);
    Reg.R1.set(0b1010);
    Reg.R2.set(0b1100);

    // R0 = R1 ^ R2
    try OP.xor(0b00000_000_001_0_00000000000000000_010);
    try std.testing.expect(Reg.R0.get() == 0b0110);

    Reg.clear();
}

test "neg" {
    Reg.R0.set(0);
    Reg.R1.set(5);

    // R0 = -R1
    try OP.neg(0b00000_000_001_000000000000000000000);
    try std.testing.expect(Reg.R0.get_signed() == -5);

    // Test with zero
    Reg.R1.set(0);
    try OP.neg(0b00000_000_001_000000000000000000000);
    try std.testing.expect(Reg.R0.get() == 0);

    // Test with a negative value
    Reg.R1.set_signed(-10);
    try OP.neg(0b00000_000_001_000000000000000000000);
    try std.testing.expect(Reg.R0.get() == 10);

    Reg.clear();
}

test "not" {
    Reg.R0.set(0);
    Reg.R1.set(0b10101010);

    // R0 = ~R1
    try OP.not(0b00000_000_001_0_00000000000000000_000);
    var expected: Instruction = 0b10101010;
    try std.testing.expect(Reg.R0.get() == ~expected);

    // Test with all ones
    Reg.R1.set(0xFFFFFFFF);
    try OP.not(0b00000_000_001_0_00000000000000000_000);
    try std.testing.expect(Reg.R0.get() == 0);

    // Test with zero
    Reg.R1.set(0);
    try OP.not(0b00000_000_001_0_00000000000000000_000);
    expected = 0;
    try std.testing.expect(Reg.R0.get() == ~expected);

    Reg.clear();
}
