const std = @import("std");
const Ch = @import("../sync_tools/Channel.zig");
const ChannelSize: usize = 100;
const Process = @import("../cpu/Process.zig").Process;
const ProcessExecutionTime: u64 = 10_000_000; // in nanoseconde (10 ms)
const Memory = @import("../cpu/Memory.zig");

const PATH = "/home/martin/Travail/Nuzima/";

pub const Distributer = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    process_list: std.ArrayList(*Process),
    process_index: usize,
    new_process_cond: std.Thread.Condition,

    pub const MessageSender = Ch.Sender(*Message, ChannelSize);

    pub const Message = struct {
        alloc: std.mem.Allocator,

        content: union(enum) {
            new_process: []u8,
        },

        pub fn newProcess(alloc: std.mem.Allocator, path: []u8) !*Message {
            const res = try alloc.create(Message);
            res.alloc = alloc;
            res.content.new_process = path;
            return res;
        }

        pub fn deinit(self: *Message) void {
            self.alloc.destroy(self);
            self.* = undefined;
        }
    };

    fn create_process(self: *Self, path: []u8) !void {
        {
            self.mutex.lock();
            defer self.mutex.unlock();
            std.debug.print("From process creator: {s}\n", .{path});

            const abs_path = try self.alloc.alloc(u8, PATH.len + path.len);
            defer self.alloc.free(abs_path);
            for (0..PATH.len) |i| abs_path[i] = PATH[i];
            for (0..path.len) |i| abs_path[PATH.len + i] = path[i];

            var process = try Process.new(self.alloc, try Memory.get_process_mem_space());
            try process.setup_memory(abs_path);
            try self.process_list.append(process);
        }
        self.new_process_cond.signal();
    }

    /// Simply using the receiver in argument to handles messages, to create process for exemple
    fn message_receiver_loop(self: *Self, receiver: *Ch.Receiver(*Message, ChannelSize)) !void {
        while (true) {
            const msg = receiver.recv() catch {
                break;
            };

            defer msg.deinit();
            switch (msg.content) {
                .new_process => |path| try self.create_process(path),
            }
        }
    }

    fn get_next(self: *Self) *Process {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.process_list.items.len == 0) {
            self.new_process_cond.wait(&self.mutex);
        }
        const p = self.process_list.items[self.process_index];
        self.process_index = (self.process_index + 1) % self.process_list.items.len;
        return p;
    }

    /// Execute instructions for a given process during ProcessExecutionTime. Then pass to the next. There is no process blocking mechanism yet.
    /// Before executing instrction of the new process, saves the registers above the stack and later pop them to restore the environnement
    fn process_loop(self: *Self) !void {
        var timer: std.time.Timer = try std.time.Timer.start();
        while (true) {
            const process = self.get_next();
            process.restore_context();
            timer.reset();
            while (timer.read() < ProcessExecutionTime and process.running) {
                const syscall = try process.next_instruction();
                if (syscall != null) {
                    try syscall.?.handle(process);
                }
            }
            process.save_context();
        }
    }

    pub fn init(alloc: std.mem.Allocator) !*MessageSender {
        const channel = try Ch.Channel(*Message, ChannelSize).init(alloc);
        var dis = try alloc.create(Self);
        dis.mutex = std.Thread.Mutex{};
        dis.process_index = 0;
        dis.process_list = std.ArrayList(*Process).init(alloc);
        dis.alloc = alloc;
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
