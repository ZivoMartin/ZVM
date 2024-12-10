const utils = @import("utils.zig");
const std = @import("std");
const Instruction = @import("instructions.zig").Instruction;

pub const ADDRESS_SIZE = 20;
pub const ADDRESS = u20;
pub const MEMORY_MAX: u64 = 1 << ADDRESS_SIZE;
pub const PROCESS_MEM_SIZE = 10_000;

var memory: [MEMORY_MAX]Instruction = undefined;
var nb_allocated_process_mem_space: usize = 0;

const MemError = error{RunOutOfMemory};

pub fn read(i: ADDRESS) !Instruction {
    return memory[@intCast(i)];
}

pub fn write(i: ADDRESS, x: Instruction) void {
    memory[@intCast(i)] = x;
}

pub fn reset() void {
    nb_allocated_process_mem_space = 0;
}

pub fn clean() void {
    for (0..memory.len) |i| memory[i] = 0;
}

pub fn get_process_mem_space() !*[PROCESS_MEM_SIZE]Instruction {
    const start = nb_allocated_process_mem_space * PROCESS_MEM_SIZE;
    if (start > MEMORY_MAX) {
        return MemError.RunOutOfMemory;
    }
    nb_allocated_process_mem_space += 1;

    return memory[start..][0..PROCESS_MEM_SIZE];
}

test "memory.get_process_mem_space" {
    const mem_space1 = try get_process_mem_space();
    mem_space1.*[0] = 10;
    try std.testing.expect(try read(0) == 10);

    const mem_space2 = try get_process_mem_space();
    mem_space2.*[0] = 11;
    try std.testing.expect(try read(PROCESS_MEM_SIZE) == 11);
    reset();
}
