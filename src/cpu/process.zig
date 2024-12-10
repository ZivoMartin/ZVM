const std = @import("std");

const memory = @import("memory.zig");
const PROCESS_MEM_SIZE = memory.PROCESS_MEM_SIZE;
const utils = @import("utils.zig");
const instructions = @import("instructions.zig");
const Instruction = instructions.Instruction;
const Reg = @import("registers.zig").Reg;
const STACK_ADDRESS = PROCESS_MEM_SIZE - 1;

const ProcessError = error{ RunOutOfMemory, InvalidExecutableSize, DecodeFailed, StackOverflow, StackEmpty, CodeReading, CodeWriting };

pub const Process = struct {
    /// A pointer to an area of the memory, the one reserved for the process
    process_memory: *[PROCESS_MEM_SIZE]Instruction,
    code_size: usize = 0,
    stack_pointer: usize = STACK_ADDRESS,

    pub fn new(process_memory: *[PROCESS_MEM_SIZE]Instruction) !Process {
        return Process{ .process_memory = process_memory };
    }

    pub fn begin(_: *const Process) void {
        Reg.COND.set(@intFromEnum(utils.FLAG.ZRO));
        Reg.PC.set(0);
    }

    fn getProgramOrigin(_: std.fs.File) !memory.ADDRESS {
        return 0;
    }

    pub fn read(self: *const Process, i: memory.ADDRESS) !Instruction {
        if (i < self.code_size) return ProcessError.CodeReading;
        return self.process_memory.*[@intCast(i)];
    }

    pub fn write(self: *Process, i: memory.ADDRESS, x: Instruction) !void {
        if (i < self.code_size) return ProcessError.CodeWriting;
        self.process_memory.*[@intCast(i)] = x;
    }

    pub fn read_instruction(self: *const Process) !Instruction {
        if (Reg.PC.get() >= self.code_size) return ProcessError.DecodeFailed;
        const instr = self.process_memory.*[Reg.PC.get()];
        Reg.PC.add(1);
        return instr;
    }

    pub fn write_instruction(self: *Process, x: Instruction) void {
        self.process_memory.*[self.code_size] = x;
        self.code_size += 1;
    }

    pub fn stack_empty(self: Process) bool {
        return self.stack_pointer == STACK_ADDRESS;
    }

    pub fn stack_peek(self: *Process) !Instruction {
        if (self.stack_empty()) return ProcessError.StackEmpty;
        return self.read(@truncate(self.stack_pointer + 1));
    }

    pub fn stack_push(self: *Process, val: Instruction) !void {
        if (self.stack_pointer == self.code_size) return ProcessError.StackOverflow;
        self.process_memory.*[self.stack_pointer] = val;
        self.stack_pointer -= 1;
    }

    pub fn stack_pop(self: *Process) !Instruction {
        if (self.stack_empty()) return ProcessError.StackEmpty;
        const res = self.read(@truncate(self.stack_pointer + 1));
        self.stack_pointer += 1;
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

    pub fn next_instruction(self: *Process) !void {
        const instr = try self.read_instruction();
        const op: instructions.OP = @enumFromInt(instr >> 27);
        std.debug.print("{}\n", .{op});
        try op.handle_instruction(instr, self);
    }
};

test "Process.next_instruction" {
    var process = try Process.new(try memory.get_process_mem_space());
    process.write_instruction(0b10010_000_1_00000000000000000101010);
    process.write_instruction(0b10010_001_1_00000000000000000000001);
    process.write_instruction(0b00000_000_001_0_00000000000000000_000);
    process.begin();
    for (0..3) |_| try process.next_instruction();
    try std.testing.expect(Reg.R0.get() == 43);
    Reg.clear();
    memory.reset();
}
