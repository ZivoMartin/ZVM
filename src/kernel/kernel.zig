const std = @import("std");
const Ch = @import("../sync_tools/Channel.zig");
const Distributer = @import("Distributer.zig").Distributer;
const Shell = @import("../shell/shell.zig");

const Thread = std.Thread;

pub const Kernel = struct {
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator) !KernelInterface {
        var kernel = ProtectedKernel.new(Kernel{ .allocator = allocator });
        const sender = try Distributer.init(allocator);

        return KernelInterface.new(kernel.allocator(), sender);
    }

    pub fn deinit(_: *Kernel) void {}
};

pub const ProtectedKernel = struct {
    kernel: Kernel,
    mutex: Thread.Mutex,
    fn new(kernel: Kernel) ProtectedKernel {
        return ProtectedKernel{ .kernel = kernel, .mutex = Thread.Mutex{} };
    }

    fn allocator(self: *const ProtectedKernel) std.mem.Allocator {
        return self.kernel.allocator;
    }
};

pub const KernelInterface = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    dis_sender: *Distributer.MessageSender,

    fn new(allocator: std.mem.Allocator, sender: *Distributer.MessageSender) KernelInterface {
        return KernelInterface{ .allocator = allocator, .dis_sender = sender };
    }

    pub fn give_command(self: *Self, path: []u8) !void {
        const elt = try Distributer.Message.newProcess(self.allocator, path);
        try self.dis_sender.send(elt);
    }

    pub fn give_shell_sender(self: *Self, sender: *Shell.ShellSender) !void {
        const msg = try Distributer.Message.newShellSender(self.allocator, sender);
        try self.dis_sender.send(msg);
    }

    pub fn deinit(self: *Self) !void {
        try self.dis_sender.deinit();
        self.* = undefined;
    }
};
