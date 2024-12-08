const std = @import("std");

const linux = std.os.linux;
const memory = @import("memory.zig");
const utils = @import("utils.zig");
const instructions = @import("instructions.zig");
const InstructionSize = instructions.InstructionSize;
const registers = @import("registers.zig");
const Reg = registers.Reg;

const uni = @cImport({
    @cInclude("unicorn/unicorn.h");
});

pub var running = true;

var act = std.os.linux.Sigaction{
    .handler = .{ .handler = utils.handle_interrupt },
    .mask = std.os.linux.empty_sigset,
    .flags = 0,
};

pub fn read_image(path: [:0]const u8) !void {
    _ = linux.sigaction(std.os.linux.SIG.INT, &act, null);
    _ = linux.sigaction(std.os.linux.SIG.TERM, &act, null);
    utils.disableCanonAndEcho();

    try memory.inject_image(path);

    Reg.COND.set(@intFromEnum(utils.FLAG.ZRO));
    Reg.PC.set(memory.PC_START);

    while (running) {
        const instr = memory.read(@truncate(Reg.PC.get())) catch {
            std.log.warn("Failed to decode\n", .{});
            std.process.exit(5);
        };
        Reg.PC.add(1);
        const op: instructions.OP = @enumFromInt(instr >> 12);
        try op.handle_instruction(instr);
    }
}
