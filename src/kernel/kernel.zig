const std = @import("std");
const Channel = @import("../sync_tools/channel/Channel.zig").Channel;
const Thread = std.Thread;

pub const Kernel = struct {
    arena: std.heap.ArenaAllocator,

    pub fn new() !KernelInterface {
        var kernel = ProtectedKernel.new(Kernel{ .arena = std.heap.ArenaAllocator.init(std.heap.page_allocator) });

        _ = try Channel(u32, 10).init(kernel.new_allocator());

        return KernelInterface.new(kernel.new_allocator());
    }

    pub fn deinit(self: *Kernel) void {
        self.arena.deinit();
    }
};

pub const ProtectedKernel = struct {
    kernel: Kernel,
    mutex: Thread.Mutex,
    fn new(kernel: Kernel) ProtectedKernel {
        return ProtectedKernel{ .kernel = kernel, .mutex = Thread.Mutex{} };
    }

    fn new_allocator(self: *ProtectedKernel) std.mem.Allocator {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.kernel.arena.allocator();
    }
};

pub const KernelInterface = struct {
    allocator: std.mem.Allocator,

    fn new(allocator: std.mem.Allocator) KernelInterface {
        return KernelInterface{ .allocator = allocator };
    }
};
