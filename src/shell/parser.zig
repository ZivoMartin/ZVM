const std = @import("std");

const BASE_MAX_ARG = 10;
var current_nb_max_arg: usize = BASE_MAX_ARG;
var current_nb_arg: usize = 0;

const ParerErr = error{DoubleNameInRedirection};

const OP = enum {
    AND,
    OR,
    PIPE,
    ANDL,

    fn try_get(word: []u8) ?OP {
        if (std.mem.eql(u8, word, "&&")) {
            return .AND;
        } else if (std.mem.eql(u8, word, "||")) {
            return .OR;
        } else if (std.mem.eql(u8, word, "|")) {
            return .PIPE;
        } else if (std.mem.eql(u8, word, ";")) {
            return .ANDL;
        } else {
            return null;
        }
    }
};

const REDIRECT = enum {
    IN, // >
    APPEND, // >>
    READ, // <<

    fn try_get(word: []u8) ?REDIRECT {
        if (std.mem.eql(u8, word, ">")) {
            return .IN;
        } else if (std.mem.eql(u8, word, "APPEND")) {
            return .APPEND;
        } else if (std.mem.eql(u8, word, "<<")) {
            return .READ;
        } else {
            return null;
        }
    }
};

pub const CommandTree = struct {
    content: union(enum) {
        redirect: struct { file: []u8, redirect: REDIRECT },
        command: struct { path: []u8, argv: [][]u8 },
        operator: OP,
        empty: void,
    },
    left: ?*CommandTree,
    right: ?*CommandTree,

    fn new(allocator: *const std.mem.Allocator) !*CommandTree {
        var res = try allocator.create(CommandTree);
        res.left = null;
        res.right = null;
        res.content = .{ .empty = {} };
        return res;
    }

    pub fn destroy(self: *CommandTree, allocator: *const std.mem.Allocator) void {
        if (self.right != null) {
            self.right.?.destroy(allocator);
        }
        if (self.left != null) {
            self.left.?.destroy(allocator);
        }
        allocator.destroy(self);
    }

    fn new_from_op(self: *CommandTree, allocator: *const std.mem.Allocator, op: OP) !*CommandTree {
        const res = try new(allocator);
        res.content = .{ .operator = op };
        res.left = self;
        res.right = try new(allocator);
        return res;
    }

    fn new_from_redirect(self: *CommandTree, allocator: *const std.mem.Allocator, redirect: REDIRECT) !*CommandTree {
        const res = try new(allocator);
        res.content = .{ .redirect = .{ .redirect = redirect, .file = &.{} } };
        res.left = self;
        return res;
    }

    pub fn conclude_command(self: *CommandTree, allocator: *const std.mem.Allocator) !void {
        switch (self.content) {
            .redirect => {},
            .command => {
                self.content.command.argv = try allocator.realloc(self.content.command.argv, current_nb_arg);
                current_nb_arg = 0;
                current_nb_max_arg = BASE_MAX_ARG;
            },
            .operator => {
                try self.right.?.conclude_command(allocator);
            },
            .empty => {},
        }
    }

    pub fn display(self: *CommandTree) void {
        self.display_helper();
        std.debug.print("\n", .{});
    }

    fn display_helper(self: *CommandTree) void {
        if (self.left != null) {
            self.left.?.display_helper();
        }
        switch (self.content) {
            .redirect => |redirect| {
                switch (redirect.redirect) {
                    .IN => std.debug.print("> ", .{}),
                    .APPEND => std.debug.print(">> ", .{}),
                    .READ => std.debug.print("<< ", .{}),
                }
                std.debug.print("{s} ", .{redirect.file});
            },
            .command => |*command| {
                std.debug.print("{s} ", .{command.path});
                for (0..command.argv.len) |i| std.debug.print("{s} ", .{command.argv[i]});
            },
            .operator => |op| {
                switch (op) {
                    .AND => std.debug.print("&& ", .{}),
                    .OR => std.debug.print("|| ", .{}),
                    .PIPE => std.debug.print("| ", .{}),
                    .ANDL => std.debug.print("; ", .{}),
                }
            },
            .empty => {},
        }
        if (self.right != null) {
            self.right.?.display_helper();
        }
    }

    fn add_last_word(self: *CommandTree, allocator: *const std.mem.Allocator, word: []u8) !*CommandTree {
        const res = try self.add_word(allocator, word);
        try res.conclude_command(allocator);
        return res;
    }

    fn add_word(self: *CommandTree, allocator: *const std.mem.Allocator, word: []u8) !*CommandTree {
        if (word.len == 0) return self;
        switch (self.content) {
            .redirect => |*redirect| {
                const op = OP.try_get(word) orelse {
                    const redirect_code = REDIRECT.try_get(word) orelse {
                        if (redirect.file.len != 0) return ParerErr.DoubleNameInRedirection;
                        redirect.file = word;
                        return self;
                    };
                    return self.new_from_redirect(allocator, redirect_code);
                };
                return self.new_from_op(allocator, op);
            },
            .command => |*command| {
                const op = OP.try_get(word) orelse {
                    const redirect = REDIRECT.try_get(word) orelse {
                        command.argv[current_nb_arg] = word;
                        if (current_nb_arg == current_nb_max_arg - 1) {
                            current_nb_max_arg *= 2;
                            command.argv = try allocator.realloc(command.argv, current_nb_max_arg);
                            @memset(command.argv[current_nb_arg + 1 ..], undefined);
                        }
                        current_nb_arg += 1;
                        return self;
                    };
                    try self.conclude_command(allocator);
                    return self.new_from_redirect(allocator, redirect);
                };
                try self.conclude_command(allocator);
                return self.new_from_op(allocator, op);
            },
            .operator => {
                self.right = try self.right.?.add_word(allocator, word);
            },
            .empty => {
                const argv = try allocator.alloc([]u8, BASE_MAX_ARG);
                self.content = .{ .command = .{ .path = word, .argv = argv } };
            },
        }

        return self;
    }
};

fn get_word(allocator: *const std.mem.Allocator, command: *const []u8, i: usize, j: usize) ![]u8 {
    const word = try allocator.alloc(u8, j - i);
    var k: usize = 0;
    while (k < (j - i)) : (k += 1) {
        word[k] = command.*[i + k];
    }
    return word;
}

pub fn parse(allocator: *const std.mem.Allocator, command: *const []u8) !*CommandTree {
    var tree = try CommandTree.new(allocator);
    var i: usize = 0;
    for (0..command.len) |j| {
        const c = command.*[j];
        if (c == ' ') {
            const word = try get_word(allocator, command, i, j);
            tree = try tree.add_word(allocator, word);
            i = j + 1;
            continue;
        }
    }
    const word = try get_word(allocator, command, i, command.len);
    tree = try tree.add_last_word(allocator, word);

    return tree;
}
