const std = @import("std");
const Thread = std.Thread;
pub const Receiver = @import("Receiver.zig").Receiver;
pub const Sender = @import("Sender.zig").Sender;
pub const Queue = @import("ChannelQueue.zig").ChannelQueue;
const Message = @import("ChannelMessage.zig").ChannelMessage;

pub fn Channel(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        receiver: Receiver(T, size),
        sender: Sender(T, size),

        pub fn init(alloc: std.mem.Allocator) !Self {
            const queue = try Queue(Message(T), size).init(alloc);

            const res = Self{
                .receiver = Receiver(T, size).init(alloc, queue),
                .sender = Sender(T, size).init(queue),
            };

            return res;
        }
    };
}
