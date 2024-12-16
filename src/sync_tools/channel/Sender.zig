const std = @import("std");
const Queue = @import("ChannelQueue.zig").ChannelQueue;
const Message = @import("ChannelMessage.zig").ChannelMessage;
const Warning = @import("ChannelMessage.zig").SenderWarning;

pub fn Sender(comptime T: type, size: usize) type {
    return struct {
        const Self = @This();

        queue: *Queue(Message(T), size),
        /// Needed to clone the sender
        alloc: std.mem.Allocator,

        pub fn init(alloc: std.mem.Allocator, queue: *Queue(Message(T), size)) !*Self {
            var res = try alloc.create(Self);
            res.queue = queue;
            res.alloc = alloc;
            return res;
        }

        pub fn send(self: *Self, elt: T) !void {
            try self.queue.send(Message(T).new(elt));
        }

        pub fn clone(self: *Self) !*Self {
            try self.queue.send(Message(T).new_warning(Warning.NewSender));
            return try Self.init(self.alloc, self.queue);
        }

        pub fn deinit(self: *Self) !void {
            try self.queue.send(Message(T).new_warning(Warning.ImClosed));
            self.alloc.destroy(self);
            self.* = undefined;
        }
    };
}
