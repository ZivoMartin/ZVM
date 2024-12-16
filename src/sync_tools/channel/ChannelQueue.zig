const std = @import("std");

pub const ChannelQueueError = error{ QueueIsEmpty, QueueIsFull, ChannelClosed };

pub fn ChannelQueue(comptime T: type, size: usize) type {
    return struct {
        const Self = @This();

        unqueue_cond: std.Thread.Condition,
        dequeue_cond: std.Thread.Condition,
        mutex: std.Thread.Mutex,
        alloc: std.mem.Allocator,
        buffer: *[size]T,
        start: usize,
        end: usize,
        len: usize,
        closed: bool,

        pub fn recv(self: *Self) !T {
            if (self.closed) {
                return ChannelQueueError.ChannelClosed;
            }
            var res: T = undefined;
            {
                self.mutex.lock();
                defer self.mutex.unlock();

                while (self.is_empty()) {
                    self.unqueue_cond.wait(&self.mutex);
                }

                res = try self.dequeue();
            }
            self.dequeue_cond.signal();
            return res;
        }

        pub fn send(self: *Self, elt: T) !void {
            if (self.closed) {
                return ChannelQueueError.ChannelClosed;
            }
            {
                self.mutex.lock();
                defer self.mutex.unlock();

                while (self.is_full()) {
                    self.dequeue_cond.wait(&self.mutex);
                }

                try self.unqueue(elt);
            }
            self.unqueue_cond.signal();
        }

        pub fn is_empty(self: *Self) bool {
            return self.len == 0;
        }

        pub fn is_full(self: *Self) bool {
            return self.len == self.buffer.len;
        }

        fn peek(self: *Self) !*T {
            if (self.is_empty()) {
                return ChannelQueueError.QueueIsEmpty;
            }
            return &self.buffer.*[self.start];
        }

        fn dequeue(self: *Self) !T {
            if (self.is_empty()) {
                return ChannelQueueError.QueueIsEmpty;
            }
            const res = self.buffer[self.start];
            self.start = (self.start + 1) % self.buffer.len;
            self.len -= 1;
            return res;
        }

        fn unqueue(self: *Self, elt: T) !void {
            if (self.is_full()) {
                return ChannelQueueError.QueueIsFull;
            }
            self.buffer[self.end] = elt;
            self.end = (self.end + 1) % self.buffer.len;
            self.len += 1;
        }

        pub fn init(alloc: std.mem.Allocator) !*Self {
            var self = try alloc.create(ChannelQueue(T, size));
            self.buffer = try alloc.create([size]T);
            self.alloc = alloc;
            self.len = 0;
            self.start = 0;
            self.closed = false;
            self.end = 0;
            self.mutex = std.Thread.Mutex{};
            self.unqueue_cond = std.Thread.Condition{};
            self.dequeue_cond = std.Thread.Condition{};
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.alloc.destroy(self.buffer);
            self.closed = true;
        }
    };
}

fn test_receiver(queue: *ChannelQueue(u32, 3)) !void {
    try std.testing.expect(try queue.recv() == 1);
    try std.testing.expect(try queue.recv() == 2);
}

test "UnqueuDequeue" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var queue = try ChannelQueue(u32, 3).init(arena.allocator());
    defer queue.deinit();

    var t = try std.Thread.spawn(.{}, test_receiver, .{queue});

    try queue.send(1);
    try queue.send(2);

    t.join();
    try std.testing.expect(queue.peek() == ChannelQueueError.QueueIsEmpty);
}
