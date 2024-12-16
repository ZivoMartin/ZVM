const CommandTree = @import("parser.zig").CommandTree;
const std = @import("std");
const KernelInterface = @import("../kernel/kernel.zig").KernelInterface;

const EvaluationError = error{};

pub fn evaluate(kernel: *KernelInterface, tree: *CommandTree) !void {
    switch (tree.content) {
        .command => |command| {
            std.debug.print("{}\n", .{command});
            try kernel.give_command(command.path);
        },
        else => {},
    }
}
