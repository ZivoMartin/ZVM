const CommandTree = @import("parser.zig").CommandTree;
const std = @import("std");
const EvaluationError = error{};

pub fn evaluate(tree: *CommandTree) !void {
    switch (tree.content) {
        .command => |command| std.debug.print("{}", .{command}),
        else => {},
    }
}
