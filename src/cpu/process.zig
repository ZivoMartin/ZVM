const std = @import("std");

const memory = @import("memory.zig");
const PROCESS_MEM_SIZE = memory.PROCESS_MEM_SIZE;
const utils = @import("utils.zig");
const instructions = @import("instructions.zig");
const Instruction = instructions.Instruction;
const InstructionSize = instructions.InstructionSize;
const Reg = @import("registers.zig").Reg;
const STACK_ADDRESS = PROCESS_MEM_SIZE - 1;

pub const SysCall: type = u32;

const ProcessError = error{ RunOutOfMemory, InvalidExecutableSize, DecodeFailed, StackOverflow, StackEmpty, CodeReading, CodeWriting };

pub const Process = struct {
    /// A pointer to an area of the memory, the one reserved for the process
    process_memory: *[PROCESS_MEM_SIZE]u8,
    code_size: usize = 0,
    stack_pointer: usize = STACK_ADDRESS,

    pub fn new(process_memory: *[PROCESS_MEM_SIZE]u8) !Process {
        return Process{ .process_memory = process_memory };
    }

    pub fn begin(_: *const Process) void {
        Reg.COND.set(@intFromEnum(utils.FLAG.ZRO));
        Reg.PC.set(0);
    }

    fn getProgramOrigin(_: std.fs.File) !memory.ADDRESS {
        return 0;
    }

    pub fn readu32(self: *const Process, i: memory.ADDRESS) !u32 {
        if (i < self.code_size) return ProcessError.CodeReading;
        return utils.read_u32(.{ self.process_memory[i], self.process_memory[i + 1], self.process_memory[i + 2], self.process_memory[i + 3] });
    }

    pub fn writeu32(self: *Process, i: memory.ADDRESS, x: u32) !void {
        if (i < self.code_size) return ProcessError.CodeWriting;
        const buffer: [4]u8 = utils.u32_bytes(x);
        self.force_write(i, &buffer);
    }

    pub fn read(self: *const Process, i: memory.ADDRESS) !u8 {
        if (i < self.code_size) return ProcessError.CodeReading;
        return self.process_memory.*[@intCast(i)];
    }

    pub fn write(self: *Process, i: memory.ADDRESS, x: u8) !void {
        if (i < self.code_size) return ProcessError.CodeWriting;
        self.process_memory[i] = x;
    }

    fn force_write(self: *Process, i: memory.ADDRESS, x: *const [4]u8) void {
        for (0..4) |k| self.process_memory.*[@intCast(i + k)] = x.*[k];
    }

    pub fn read_instruction(self: *const Process) !Instruction {
        if (Reg.PC.get() >= self.code_size) return ProcessError.DecodeFailed;
        const pc = Reg.PC.get();
        const instr = utils.read_u32(.{ self.process_memory[pc], self.process_memory[pc + 1], self.process_memory[pc + 2], self.process_memory[pc + 3] });
        Reg.PC.add(InstructionSize);
        return instr;
    }

    pub fn write_instruction(self: *Process, x: Instruction) void {
        const buffer: [4]u8 = utils.u32_bytes(x);
        self.force_write(@truncate(self.code_size), &buffer);
        self.code_size += InstructionSize;
    }

    pub fn stack_empty(self: Process) bool {
        return self.stack_pointer == STACK_ADDRESS;
    }

    pub fn stack_peek(self: *Process) !Instruction {
        if (self.stack_empty()) return ProcessError.StackEmpty;
        return utils.read_u32(.{ self.process_memory[self.stack_pointer + 4], self.process_memory[self.stack_pointer + 3], self.process_memory[self.stack_pointer + 2], self.process_memory[self.stack_pointer + 1] });
    }

    pub fn stack_push(self: *Process, val: Instruction) !void {
        if (self.stack_pointer == self.code_size) return ProcessError.StackOverflow;
        const buffer: [4]u8 = utils.u32_bytes(val);

        for (0..4) |k| self.process_memory.*[self.stack_pointer - k] = buffer[k];
        self.stack_pointer -= 4;
    }

    pub fn stack_pop(self: *Process) !Instruction {
        const res = try self.stack_peek();
        self.stack_pointer += 4;
        return res;
    }

    pub fn setup_memory(self: *Process, image_path: [:0]const u8) !void {
        const file = try std.fs.cwd().openFile(image_path, .{});
        defer file.close();
        const origin = try getProgramOrigin(file);
        var buffer: [4]u8 = undefined;
        var index = origin;
        while (true) : (index += 1) {
            const bytes_read = try file.read(&buffer);
            if (bytes_read == 0) break;
            if (bytes_read != 4) return ProcessError.InvalidExecutableSize;
            if (index >= self.process_memory.len) return ProcessError.RunOutOfMemory;
            self.write_instruction(std.mem.readInt(Instruction, &buffer, .big));
        }
    }

    pub fn next_instruction(self: *Process) !?SysCall {
        const instr = try self.read_instruction();
        const op: instructions.OP = @enumFromInt(instr >> 27);
        std.debug.print("{}\n", .{op});
        try op.handle_instruction(instr, self);
        return op.get_syscall();
    }
};

test "write_read_u32" {
    var process = try Process.new(try memory.get_process_mem_space());
    try process.writeu32(10, 30);
    try std.testing.expect(try process.readu32(10) == 30);
}

test "Process.next_instruction" {
    var process = try Process.new(try memory.get_process_mem_space());
    process.write_instruction(0b10010_000_1_00000000000000000101010);
    process.write_instruction(0b10010_001_1_00000000000000000000001);
    process.write_instruction(0b00000_000_001_0_00000000000000000_000);
    process.begin();
    for (0..3) |_| _ = try process.next_instruction();
    try std.testing.expect(Reg.R0.get() == 43);
    Reg.clear();
    memory.reset();
}
