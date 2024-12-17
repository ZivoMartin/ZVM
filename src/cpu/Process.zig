const std = @import("std");

const Memory = @import("Memory.zig");
const PROCESS_MEM_SIZE = Memory.PROCESS_MEM_SIZE;
const utils = @import("utils.zig");
const instructions = @import("instructions.zig");
const Instruction = instructions.Instruction;
const InstructionSize = instructions.InstructionSize;
const Reg = @import("registers.zig").Reg;

const ContextSaver = @import("ContextSaver.zig").ContextSaver;

const ErrorMessageAddr = 0x100;
const STACK_ADDRESS = PROCESS_MEM_SIZE - 1;
const Syscall = @import("../kernel/syscall.zig").Syscall;

const ProcessError = error{ RunOutOfMemory, InvalidExecutableSize, DecodeFailed, StackOverflow, StackEmpty, CodeReading, CodeWriting };

pub const Process = struct {
    /// A pointer to an area of the memory, the one reserved for the process
    process_memory: *[PROCESS_MEM_SIZE]u8,
    code_size: usize = 0,
    stack_pointer: usize = STACK_ADDRESS,
    running: bool = true,
    allocator: std.mem.Allocator,
    context_saver: ContextSaver,

    pub fn new(allocator: std.mem.Allocator, process_memory: *[PROCESS_MEM_SIZE]u8) !*Process {
        const p = try allocator.create(Process);
        p.process_memory = process_memory;
        p.allocator = allocator;
        p.code_size = 0;
        p.stack_pointer = STACK_ADDRESS;
        p.running = true;
        p.context_saver = ContextSaver.new();

        return p;
    }

    /// TODO: Should call a memory function  to give to the next process the memory of this one
    pub fn deinit(_: *Process) void {}

    pub fn restore_context(self: *Process) void {
        self.context_saver.restore_context();
    }

    pub fn save_context(self: *Process) void {
        self.context_saver.save();
    }

    fn getProgramOrigin(f: *const std.fs.File) !Memory.ADDRESS {
        var buffer: [4]u8 = undefined;
        _ = try f.read(&buffer);
        return @truncate(utils.read_u32(buffer));
    }

    pub fn readu32(self: *const Process, i: Memory.ADDRESS) !u32 {
        if (i < self.code_size) return ProcessError.CodeReading;
        return utils.read_u32(.{ self.process_memory[i], self.process_memory[i + 1], self.process_memory[i + 2], self.process_memory[i + 3] });
    }

    pub fn writeu32(self: *Process, i: Memory.ADDRESS, x: u32) !void {
        if (i < self.code_size) return ProcessError.CodeWriting;
        const buffer: [4]u8 = utils.u32_bytes(x);
        self.force_write(i, &buffer);
    }

    pub fn read(self: *const Process, i: Memory.ADDRESS) u8 {
        return self.process_memory.*[@intCast(i)];
    }

    pub fn write(self: *Process, i: Memory.ADDRESS, x: u8) !void {
        if (i < self.code_size) return ProcessError.CodeWriting;
        self.process_memory[i] = x;
    }

    fn force_write(self: *Process, i: Memory.ADDRESS, x: *const [4]u8) void {
        for (0..4) |k| self.process_memory.*[@intCast(i + k)] = x.*[k];
    }

    pub fn write_string(self: *Process, addr: Memory.ADDRESS, s: []const u8) void {
        for (s, addr..) |c, i| {
            if (c == 0) {
                break;
            }
            self.process_memory.*[i] = c;
        }
    }

    pub fn read_instruction(self: *const Process) !Instruction {
        if (Reg.PC.get() >= self.code_size) return ProcessError.DecodeFailed;
        const pc = Reg.PC.get();
        const instr = utils.read_u32(.{ self.process_memory[pc], self.process_memory[pc + 1], self.process_memory[pc + 2], self.process_memory[pc + 3] });
        Reg.PC.add(InstructionSize);
        return instr;
    }

    pub fn mem_read(self: *Process, addr: Memory.ADDRESS) []const u8 {
        var i = addr;
        while (self.read(i) != 0) i += 1;
        return self.process_memory[addr .. i + 1];
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

    pub fn put_error(self: *Process, err: []const u8) void {
        Reg.R7.set(ErrorMessageAddr);
        self.write_string(ErrorMessageAddr, @ptrCast(err));
    }

    pub fn setup_memory(self: *Process, image_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(image_path, .{});
        defer file.close();
        const origin = try getProgramOrigin(&file);
        Reg.PC.set(origin);
        self.context_saver.set_reg(Reg.PC, origin);
        var buffer: [1]u8 = undefined;
        var index: u20 = 0;
        while (true) : (index += 1) {
            const bytes_read = try file.read(&buffer);
            if (bytes_read == 0) break;
            if (index >= self.process_memory.len) return ProcessError.RunOutOfMemory;
            try self.write(index, buffer[0]);
            self.code_size += 1;
        }
    }

    pub fn next_instruction(self: *Process) !?Syscall {
        const instr = try self.read_instruction();
        const op: instructions.OP = @enumFromInt(instr >> 27);
        std.debug.print("{}\n", .{op});
        try op.handle_instruction(instr, self);
        return op.get_syscall();
    }
};

test "write_read_u32" {
    var process = try Process.new(try Memory.get_process_mem_space());
    try process.writeu32(10, 30);
    try std.testing.expect(try process.readu32(10) == 30);
}

test "Process.next_instruction" {
    var process = try Process.new(try Memory.get_process_mem_space());
    process.write_instruction(0b10010_000_1_00000000000000000101010);
    process.write_instruction(0b10010_001_1_00000000000000000000001);
    process.write_instruction(0b00000_000_001_0_00000000000000000_000);
    process.restore_context();
    for (0..3) |_| _ = try process.next_instruction();
    try std.testing.expect(Reg.R0.get() == 43);
    Reg.clear();
    Memory.reset();
}
