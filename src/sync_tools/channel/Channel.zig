const std = @import("std");
const Thread = std.Thread;
pub const ReceiverError = @import("Receiver.zig").ReceiverError;
pub const Receiver = @import("Receiver.zig").Receiver;
pub const Sender = @import("Sender.zig").Sender;
pub const Queue = @import("ChannelQueue.zig").ChannelQueue;
const Message = @import("ChannelMessage.zig").ChannelMessage;
const ChannelQueueError = @import("ChannelQueue.zig").ChannelQueueError;

pub fn Channel(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        receiver: *Receiver(T, size),
        sender: *Sender(T, size),

        pub fn init(alloc: std.mem.Allocator) !Self {
            const queue = try Queue(Message(T), size).init(alloc);

            const res = Self{
                .receiver = try Receiver(T, size).init(alloc, queue),
                .sender = try Sender(T, size).init(alloc, queue),
            };

            return res;
        }
    };
}

fn test_receiver(receiver: *Receiver(u32, 2)) !void {
    try std.testing.expect(try receiver.recv() == 1);
}

test "Channel" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var channel = try Channel(u32, 2).init(arena.allocator());

    var t = try std.Thread.spawn(.{}, test_receiver, .{channel.receiver});

    var other_sender = try channel.sender.clone();

    try channel.sender.send(1);
    try channel.sender.deinit();

    t.join();

    try other_sender.send(27);
    try std.testing.expect(try channel.receiver.recv() == 27);
    try other_sender.deinit();

    try std.testing.expect(channel.receiver.recv() == ReceiverError.ReceiverIsClosed);
}
