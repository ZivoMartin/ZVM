const std = @import("std");
const Ch = @import("../sync_tools/Channel.zig");
const ChannelSize: usize = 100;
const Process = @import("../cpu/Process.zig").Process;
const ProcessExecutionTime: u64 = 10_000_000; // in nanoseconde (10 ms)
const Memory = @import("../cpu/Memory.zig");
const Shell = @import("../shell/shell.zig");
const FS = @import("../fs/fs.zig");

const FILE_NOT_FOUND_ERR = "File not found: ";

const PATH = "/home/martin/Travail/Nuzima/";

pub const Distributer = struct {
    const Self = @This();

    fs: *FS.FS,
    alloc: std.mem.Allocator,
    mutex: std.Thread.Mutex,
    process_list: std.ArrayList(*Process),
    process_index: usize,
    new_process_cond: std.Thread.Condition,
    shell_sender: ?*Shell.ShellSender,

    pub const MessageSender = Ch.Sender(*Message, ChannelSize);

    pub const Message = struct {
        alloc: std.mem.Allocator,

        content: union(enum) { new_process: []u8, shell_sender: *Shell.ShellSender },

        pub fn newProcess(alloc: std.mem.Allocator, path: []u8) !*Message {
            const res = try alloc.create(Message);
            res.alloc = alloc;
            res.content = .{ .new_process = path };
            return res;
        }

        pub fn newShellSender(alloc: std.mem.Allocator, shell_sender: *Shell.ShellSender) !*Message {
            const res = try alloc.create(Message);
            res.alloc = alloc;
            res.content.shell_sender = shell_sender;
            return res;
        }

        pub fn deinit(self: *Message) void {
            self.alloc.destroy(self);

            self.* = undefined;
        }
    };

    fn file_not_found(self: *Self, path: []const u8) !void {
        if (self.shell_sender != null) {
            const len = FILE_NOT_FOUND_ERR.len + path.len + 1;
            const err = try self.alloc.alloc(u8, len);
            var i: usize = 0;
            for (FILE_NOT_FOUND_ERR) |c| {
                err[i] = c;
                i += 1;
            }
            for (path) |c| {
                err[i] = c;
                i += 1;
            }
            err[i] = '\n';
            try self.shell_sender.?.send(try Shell.ShellMessage.newStderr(self.alloc, err));
            try self.shell_sender.?.send(try Shell.ShellMessage.newProcessEnded(self.alloc));
        }
    }

    fn create_process(self: *Self, path: []const u8) !void {
        {
            self.mutex.lock();
            defer self.mutex.unlock();
            std.debug.print("From process creator: {s}\n", .{path});

            const abs_path = try self.alloc.alloc(u8, PATH.len + path.len);
            defer self.alloc.free(abs_path);
            for (0..PATH.len) |i| abs_path[i] = PATH[i];
            for (0..path.len) |i| abs_path[PATH.len + i] = path[i];

            var process = try Process.new(self.alloc, try Memory.get_process_mem_space());
            process.setup_memory(abs_path) catch {
                try self.file_not_found(path);
                return;
            };
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
                .shell_sender => |sender| self.shell_sender = sender,
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
            while (timer.read() < ProcessExecutionTime) {
                const syscall = try process.next_instruction();
                if (syscall != null) {
                    try syscall.?.handle(self, process);
                }
                if (!process.running) {
                    if (self.shell_sender != null) {
                        try self.shell_sender.?.send(try Shell.ShellMessage.newProcessEnded(self.alloc));
                    }
                    var i: usize = 0;
                    while (self.process_list.items[i] != process) i += 1;
                    _ = self.process_list.orderedRemove(i);
                    break;
                }
            }
            if (process.running) {
                process.save_context();
            } else {
                process.deinit();
            }
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
        if (self.shell_sender != null) {
            self.shell_sender.deinit();
        }

        self.list.deinit();
        self.alloc.destroy(self);
        self.* = undefined;
    }
};
