const std = @import("std");
const Queue = @import("ChannelQueue.zig").ChannelQueue;
const Message = @import("ChannelMessage.zig").ChannelMessage;
const Warning = @import("ChannelMessage.zig").SenderWarning;

pub fn Sender(comptime T: type, size: usize) type {
    return struct {
        const Self = @This();

        queue: *Queue(Message(T), size),

        pub fn init(queue: *Queue(Message(T), size)) Self {
            return Self{ .queue = queue };
        }

        pub fn send(self: *Self, elt: T) !void {
            try self.queue.send(Message.new(elt));
        }

        pub fn clone(self: *Self) Self {
            try self.queue.send(Message.new_warning(Warning.NewSender));
            return Self{ .queue = self.queue };
        }

        pub fn deinit(self: *Self) void {
            try self.queue.send(Message.new_warning(Warning.ImClosed));
            self.* = undefined;
        }
    };
}
