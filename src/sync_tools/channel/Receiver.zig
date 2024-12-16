const std = @import("std");
const Queue = @import("ChannelQueue.zig").ChannelQueue;
const Message = @import("ChannelMessage.zig").ChannelMessage;

pub const ReceiverError = error{ReceiverIsClosed};

pub fn Receiver(comptime T: type, size: usize) type {
    return struct {
        const Self = @This();

        queue: *Queue(Message(T), size),
        /// Needed to free the queue
        alloc: std.mem.Allocator,

        nb_sender: usize = 1,

        pub fn init(alloc: std.mem.Allocator, queue: *Queue(Message(T), size)) Self {
            return Self{ .alloc = alloc, .queue = queue };
        }

        pub fn recv(self: *Self) !T {
            const message = self.queue.recv();
            switch (message) {
                .elt => |value| return value,
                .sender_warning => |warn| {
                    switch (warn) {
                        .NewSender => self.sender += 1,
                        .ImClosed => {
                            self.nb_sender -= 1;
                            if (self.nb_sender == 0) {
                                return ReceiverError.ReceiverIsClosed;
                            }
                        },
                    }
                    return self.recv();
                },
            }
        }

        pub fn deinit(self: *Self) !void {
            try self.queue.deinit();
            try self.alloc.free(self.queue);
            self.* = undefined;
        }
    };
}
