const utils = @import("utils.zig");
const registers = @import("registers.zig");
const memory = @import("memory.zig");
const traps = @import("traps.zig");
const std = @import("std");
const Process = @import("process.zig").Process;

pub const Instruction: type = u32;
pub const InstructionSigned: type = i32;

const Reg = registers.Reg;

pub const JUMP_CODE = enum(u3) { JMP = 0, JE, JH, JL, JLE, JHE };

pub const OP = enum(u5) {
    /// Add two values (OK)
    ADD = 0x0,
    /// Multiply two values
    MUL = 0x1,
    /// Sub two values
    SUB = 0x2,
    /// Divide two values
    DIV = 0x3,
    /// Mod of two values
    MOD = 0x4,
    /// Put the negation of a first register in a memory spot
    NEG = 0x5,
    /// Shift left for bitwise operations
    SHL = 0x6,
    /// Shift right for bitwise operations
    SHR = 0x7,
    /// Perform binary and over two values
    AND = 0x8,
    /// Perform binary or over two values
    OR = 0x9,
    /// Perform binary xor over two values
    XOR = 0xA,
    /// Perform binary not over a values
    NOT = 0xB,
    /// Jmp to an address of the code, conatins a jump code indicates the kind of jump
    JMP = 0xC,
    /// Provoc an interruption
    INT = 0xD,
    /// Push a value on the stack, support pushf and pushr
    PUSH = 0xE,
    /// Pop a value of the stack, support popf and popr
    POP = 0xF,
    /// Pop a value of the stack and perform jump
    RET = 0x10,
    /// Push the stack pointer and jmp
    CALL = 0x11,
    /// Mov a value in a register or a memory zone
    MOV = 0x12,
    /// Read a value in the memory it in a register
    READ = 0x13,
    /// Write a value in the memory
    WRITE = 0x14,
    /// Compare two values, actualise the condition flags
    CMP = 0x15,
    /// Set all the registers at 0
    CLEAR = 0x16,
    /// Stop the program
    HALT = 0x17,
    /// Print the current state of registers/memory (helpful for debugging in a VM).
    TRACE = 0x18,
    /// Duplicate the top value on the stack.
    DUP = 0x19,
    /// Swap the top two values on the stack.
    SWAP = 0x1A,

    const InstructionProcessingError = error{
        InvalidInstruction,
        DivisionByZero,
        MemoryAccessViolation,
        StackOverflow,
    };

    pub fn handle_instruction(self: OP, instr: Instruction, process: *Process) !void {
        try switch (self) {
            .ADD => add(instr),
            .MUL => mul(instr),
            .SUB => sub(instr),
            .DIV => div(instr),
            .MOD => mod(instr),
            .NEG => neg(instr),
            .SHL => shl(instr),
            .SHR => shr(instr),
            .AND => _and(instr),
            .OR => _or(instr),
            .XOR => xor(instr),
            .NOT => not(instr),
            .JMP => jmp(instr),
            .INT => int(instr),
            .PUSH => push(instr, process),
            .POP => pop(instr, process),
            .RET => ret(instr),
            .CALL => call(instr),
            .MOV => mov(instr),
            .READ => read(instr, process),
            .WRITE => write(instr, process),
            .CMP => cmp(instr),
            .CLEAR => clear(instr),
            .HALT => halt(instr),
            .TRACE => trace(instr),
            .DUP => dup(instr),
            .SWAP => swap(instr),
        };
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

    /// Represents an arithmetic operation with a destination register and two operands.
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

    fn cmp(instr: Instruction) !void {
        const v1 = get_r0(instr).get();
        const imm_flag = (instr >> 23) & 0x1;

        const v2 = if (imm_flag != 0)
            get_immediate_value(instr)
        else
            get_r2(instr).get();

        if (v1 == v2) {
            Reg.set_flag_zero();
        } else if (v1 < v2) {
            Reg.set_flag_neg();
        } else {
            Reg.set_flag_pos();
        }
    }

    fn trace(_: Instruction) !void {
        Reg.trace();
    }

    fn clear(_: Instruction) !void {
        Reg.clear();
    }

    fn mov(instr: Instruction) !void {
        const r0 = get_r0(instr);
        const imm_flag = (instr >> 23) & 0x1;
        if (imm_flag != 0) {
            r0.set(get_immediate_value(instr));
        } else {
            r0.set(get_r2(instr).get());
        }
    }

    fn read(instr: Instruction, process: *Process) !void {
        const r0 = get_r0(instr);
        const addr: u20 = @truncate(get_immediate_value(instr));
        r0.set(try process.read(addr));
    }

    fn write(instr: Instruction, process: *Process) !void {
        const r0 = get_r0(instr);
        const addr: u20 = @truncate(get_immediate_value(instr));
        try process.write(addr, r0.get());
    }

    fn ret(_: Instruction) !void {}
    fn call(_: Instruction) !void {}
    fn dup(_: Instruction) !void {}
    fn swap(_: Instruction) !void {}

    fn push(instr: Instruction, process: *Process) !void {
        try process.stack_push(if ((instr >> 26) & 1 != 0) get_immediate_value(instr) else get_r2(instr).get());
    }

    fn pop(instr: Instruction, process: *Process) !void {
        get_r2(instr).set(try process.stack_pop());
    }

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
test "jump" {
    Reg.PC.set(0);
}

test "mov" {
    // Test moving an immediate value into a register
    Reg.R0.set(0);

    // R0 = immediate 42
    try OP.mov(0b00000_000_1_00000000000000000101010);
    try std.testing.expect(Reg.R0.get() == 42);

    // R0 = immediate -1 (20-bit two's complement negative number)
    try OP.mov(0b00000_000_1_11111111111111111111111);
    try std.testing.expect(Reg.R0.get_signed() == -1);

    // Test moving a value from another register
    Reg.R1.set(1337);
    Reg.R0.set(0);

    // R0 = R1
    try OP.mov(0b00000_000_000_0_000000000000000000001);
    try std.testing.expect(Reg.R0.get() == 1337);

    // Another example: R2 = R1
    Reg.R2.set(0);
    try OP.mov(0b00000_010_0_00000000000000000000001);
    try std.testing.expect(Reg.R2.get() == 1337);

    Reg.clear();
}

test "cmp" {
    // Test comparison with immediate value
    Reg.R0.set(10);
    Reg.R1.set(0);

    // R0 - 5
    try OP.cmp(0b00000_000_1_00000000000000000101);
    try std.testing.expect(Reg.COND.get() == @intFromEnum(utils.FLAG.POS));

    // R0 - 10
    try OP.cmp(0b00000_000_1_00000000000000000001010);
    try std.testing.expect(Reg.COND.get() == @intFromEnum(utils.FLAG.ZRO));

    // R0 - 15
    try OP.cmp(0b00000_000_1_00000000000000000001111);
    try std.testing.expect(Reg.COND.get() == @intFromEnum(utils.FLAG.NEG));

    // Test comparison with another register
    Reg.R0.set(20);
    Reg.R2.set(15);

    // R0 - R2
    try OP.cmp(0b00000_000_0_00000000000000000000010);
    try std.testing.expect(Reg.COND.get() == @intFromEnum(utils.FLAG.POS));

    Reg.R2.set(20);

    // R0 - R2
    try OP.cmp(0b00000_000_0_00000000000000000000010);
    try std.testing.expect(Reg.COND.get() == @intFromEnum(utils.FLAG.ZRO));

    Reg.R2.set(25);

    // R0 - R2
    try OP.cmp(0b00000_000_0_00000000000000000000010);
    try std.testing.expect(Reg.COND.get() == @intFromEnum(utils.FLAG.NEG));

    Reg.clear();
}

test "read" {
    var process = try Process.new(try memory.get_process_mem_space());
    process.begin();

    try process.write(30, 10);
    try OP.read(0b00000_000_0000_00000000000000011110, &process);
    try std.testing.expect(Reg.R0.get() == 10);

    memory.clean();
}

test "write" {
    var process = try Process.new(try memory.get_process_mem_space());
    process.begin();

    Reg.R0.set(10);
    try OP.write(0b00000_000_0000_00000000000000011110, &process);
    try std.testing.expect(try process.read(30) == 10);

    memory.clean();
}

test "push" {
    var process = try Process.new(try memory.get_process_mem_space());
    process.begin();

    Reg.R1.set(1337);

    try OP.push(0b00000_1_00000000000000000000101010, &process);
    try std.testing.expect(try process.stack_peek() == 42);

    try OP.push(0b00000_0_00000000000000000000000001, &process);
    try std.testing.expect(try process.stack_peek() == 1337);

    try std.testing.expect(try process.stack_pop() == 1337);
    try std.testing.expect(try process.stack_pop() == 42);

    Reg.clear();
    memory.clean();
}

test "pop" {
    var process = try Process.new(try memory.get_process_mem_space());
    process.begin();

    try process.stack_push(42);
    try process.stack_push(1337);

    Reg.R0.set(0);
    try OP.pop(0b00000_00000000000000000000000000, &process);
    try std.testing.expect(Reg.R0.get() == 1337);

    Reg.R1.set(0);
    try OP.pop(0b00000_000000000000000000000000001, &process);
    try std.testing.expect(Reg.R1.get() == 42);

    try std.testing.expect(process.stack_empty());

    Reg.clear();
    memory.clean();
}
