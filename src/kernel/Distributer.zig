const std = @import("std");
const Ch = @import("../sync_tools/Channel.zig");
const ChannelSize: usize = 100;
const Process = @import("../cpu/Process.zig").Process;
const ProcessExecutionTime = 10; // in ms

pub const Distributer = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    process_list: std.ArrayList(*Message),

    pub const MessageSender = Ch.Sender(*Message, ChannelSize);

    pub const Message = union(enum) {
        new_process: []u8,

        pub fn newProcess(alloc: *const std.mem.Allocator, path: []u8) !*Message {
            const res = try alloc.create(Message);
            res.new_process = path;
            return res;
        }

        pub fn deinit(self: *Message, alloc: *const std.mem.Allocator) void {
            alloc.destroy(self);
        }
    };

    fn create_process(self: *Self, path: []u8) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        std.debug.print("From process creator: {s}\n", .{path});
        // TODO: Create the process and insert it in the list
    }

    /// Simply using the receiver in argument to handles messages, to create process for exemple
    fn message_receiver_loop(self: *Self, receiver: *Ch.Receiver(*Message, ChannelSize)) !void {
        while (true) {
            const msg = receiver.recv() catch {
                break;
            };

            defer msg.deinit(&self.alloc);
            switch (msg.*) {
                .new_process => |path| self.create_process(path),
            }
        }
    }

    /// Execute instructions for a given process during ProcessExecutionTime. Then pass to the next. There is no process blocking mechanism yet.
    /// Before executing instrction of the new process, saves the registers above the stack and later pop them to restore the environnement
    fn process_loop(_: *Self) !void {}

    pub fn init(alloc: std.mem.Allocator) !*MessageSender {
        const channel = try Ch.Channel(*Message, ChannelSize).init(alloc);
        var dis = try alloc.create(Self);
        dis.mutex = std.Thread.Mutex{};
        dis.process_list = std.ArrayList(*Message).init(alloc);
        _ = try std.Thread.spawn(.{}, message_receiver_loop, .{ dis, channel.receiver });
        _ = try std.Thread.spawn(.{}, process_loop, .{dis});
        return channel.sender;
    }

    pub fn deinit(self: *Self) void {
        self.list.deinit();
        self.alloc.destroy(self);
        self.* = undefined;
    }
};
