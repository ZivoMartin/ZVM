const std = @import("std");
const File = std.fs.File;
const clib = @cImport({
    @cInclude("time.h");
    @cInclude("sys/select.h");
    @cInclude("poll.h");
    @cInclude("signal.h");
    @cInclude("termios.h");
    @cInclude("unistd.h");
});

const MEMORY_MAX: u64 = 1 << 16;

var running = true;
var memory: [MEMORY_MAX]u16 = undefined;
const PC_START = 0x3000;

const Reg = enum(u8) {
    R0 = 0,
    R1,
    R2,
    R3,
    R4,
    R5,
    R6,
    R7,
    PC,
    COND,

    var reg: [@typeInfo(Reg).Enum.fields.len]u16 = undefined;

    pub fn set(self: Reg, val: u16) void {
        reg[@intFromEnum(self)] = val;
    }

    pub fn get(self: Reg) u16 {
        return reg[@intFromEnum(self)];
    }

    pub fn add(self: Reg, x: u16) void {
        self.set(self.get() + x);
    }

    fn update_flags(self: Reg) void {
        const r = self.get();
        if (r == 0) {
            Reg.COND.set(@intFromEnum(FLAG.ZRO));
        } else if (r < 0) {
            Reg.COND.set(@intFromEnum(FLAG.NEG));
        } else {
            Reg.COND.set(@intFromEnum(FLAG.POS));
        }
    }
};

const TR = enum(u16) {
    GETC = 0x20, //  get character from keyboard, not echoed onto the terminal
    OUT = 0x21, //  output a character
    PUTS = 0x22, //  output a word string
    IN = 0x23, //  get character from keyboard, echoed onto the terminal
    PUTSP = 0x24, //  output a byte string
    HALT = 0x25, //  halt the program

    fn process(self: TR) !void {
        const stdout = std.io.getStdOut().writer();
        var buffered_writer = std.io.bufferedWriter(stdout);
        const writer = buffered_writer.writer();
        switch (self) {
            .GETC => {
                const stdin = std.io.getStdIn().reader();
                const c = try stdin.readByte();
                Reg.R0.set(@as(u16, c));
                Reg.R0.update_flags();
            },
            .OUT => {
                const c: u8 = @truncate(Reg.R0.get());
                try writer.writeByte(c);
                try buffered_writer.flush();
            },
            .PUTS => {
                for (memory[Reg.R0.get()..]) |c| {
                    if (c == 0) break;
                    try writer.writeByte(@truncate(c));
                }
                try buffered_writer.flush();
            },
            .IN => {
                try writer.writeAll("> ");
                try TR.OUT.process();
                try writer.writeByte(@truncate(Reg.R0.get()));
                try writer.writeByte('\n');
            },
            .PUTSP => {
                for (memory[Reg.R0.get()..]) |c| {
                    const c1: u8 = @truncate(c);
                    const c2: u8 = @truncate(c >> 8);
                    if (c1 == 0) break;
                    try writer.writeByte(@truncate(c1));
                    if (c2 == 0) break;
                    try writer.writeByte(@truncate(c2));
                }
                try buffered_writer.flush();
            },
            .HALT => {
                try writer.writeAll("End of processing");
                try buffered_writer.flush();
                running = false;
            },
        }
    }
};

fn sign_extend(x: u16, comptime bit_count: u32) u16 {
    if (((x >> (bit_count - 1)) & 1) == 1) {
        const mask: u16 = @truncate((0xFFFF << bit_count));
        return x | mask;
    }
    return x;
}

const OP = enum(u8) {
    BR = 0,
    ADD,
    LD,
    ST,
    JSR,
    AND,
    LDR,
    STR,
    RTI,
    NOT,
    LDI,
    STI,
    JMP,
    RES,
    LEA,
    TRAP,

    fn handle_instruction(instr: u16) !void {
        here:
        const op: OP = @enumFromInt(instr >> 12);
        std.debug.print("{} {}\n", .{ op, Reg.PC.get() });
        switch (op) {
            .BR => {
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                const cond_flag = (instr >> 9) & 0x7;
                if (cond_flag & Reg.COND.get() != 0) {
                    Reg.PC.add(pc_offset);
                }
            },
            .ADD => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const imm_flag = (instr >> 5) & 0x1;
                if (imm_flag == 1) {
                    const imm5 = sign_extend(instr & 0x1F, 5);
                    r0.set(r1.get() + imm5);
                } else {
                    const r2: Reg = @enumFromInt(instr & 0x7);
                    r0.set(r1.get() + r2.get());
                }
                r0.update_flags();
            },
            .LD => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                r0.set(try mem_read(Reg.PC.get() + pc_offset));
                r0.update_flags();
            },
            .ST => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                mem_write(Reg.PC.get() + pc_offset, r0.get());
            },
            .JSR => {
                const long_flag = (instr >> 11) & 1;
                Reg.R7.set(Reg.PC.get());
                if (long_flag == 1) {
                    const long_pc_offset = sign_extend(instr & 0x7FF, 11);
                    Reg.PC.add(long_pc_offset);
                } else {
                    const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                    Reg.PC.set(r1.get());
                }
            },
            .AND => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const imm_flag = (instr >> 5) & 0x1;
                if (imm_flag == 1) {
                    const imm5 = sign_extend(instr & 0x1F, 5);
                    r0.set(r1.get() & imm5);
                } else {
                    const r2: Reg = @enumFromInt(instr & 0x7);
                    r0.set(r1.get() & r2.get());
                }
                r0.update_flags();
            },
            .LDR => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const offset = sign_extend(instr & 0x3F, 6);
                r0.set(try mem_read(r1.get() + offset));
                r0.update_flags();
            },
            .STR => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const offset = sign_extend((instr & 0x3F), 6);
                mem_write(r1.get() + offset, r0.get());
            },
            .RTI => {
                std.debug.print("The RTI instruction is not supported.", .{});
                std.process.exit(1);
            },
            .NOT => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                r0.set(~r1.get());
            },
            .LDI => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                r0.set(try mem_read(Reg.PC.get()) + pc_offset);
            },
            .STI => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                mem_write(try mem_read(Reg.PC.get() + pc_offset), r0.get());
            },
            .JMP => {
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                Reg.PC.set(r1.get());
            },
            .RES => {
                std.debug.print("The res instruction is not supported.", .{});
                std.process.exit(1);
            },
            .LEA => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                r0.set(try mem_read(Reg.PC.get() + pc_offset));
                r0.update_flags();
            },
            .TRAP => {
                Reg.R7.set(Reg.PC.get());
                const trap: TR = @enumFromInt(instr & 0xFF);
                try trap.process();
            },
        }
    }
};

const FLAG = enum(u16) {
    POS = 1 << 0,
    ZRO = 1 << 1,
    NEG = 1 << 2,
};

const MR = enum(u16) {
    KBSR = 0xFE00, // keyboard status
    KBDR = 0xFE02, // keyboard data
};

fn check_key() bool {
    var readfds: clib.fd_set = undefined;
    var timeout: clib.timeval = undefined;
    timeout.tv_sec = 0;
    timeout.tv_usec = 0;
    return clib.select(1, &readfds, 0, 0, &timeout) != 0;
}

var original_tio: clib.termios = undefined;

fn disableInputBuffering() void {
    const stdin_fd = std.os.linux.STDIN_FILENO;
    _ = clib.tcgetattr(stdin_fd, &original_tio);
    var new_tio: clib.termios = original_tio;
    new_tio.c_lflag &= @bitCast(~clib.ICANON & ~clib.ECHO);
    _ = clib.tcsetattr(stdin_fd, clib.TCSANOW, &new_tio);
}

fn restoreInputBuffering() void {
    const stdin_fd = std.os.linux.STDIN_FILENO;
    _ = clib.tcsetattr(stdin_fd, clib.TCSANOW, &original_tio);
}

fn mem_read(i: u16) !u16 {
    if (i == @intFromEnum(MR.KBSR)) {
        if (check_key()) {
            const stdin = std.io.getStdIn().reader();
            const c = @as(u16, try stdin.readByte());
            memory[@intFromEnum(MR.KBSR)] = (1 << 15);
            memory[@intFromEnum(MR.KBDR)] = @as(u16, c);
        } else {
            memory[@intFromEnum(MR.KBSR)] = 0;
        }
    }
    return memory[i];
}

fn mem_write(i: u16, x: u16) void {
    memory[i] = x;
}

fn read_image_file(f: File) !void {
    const reader = File.reader(f);
    const origin = try reader.readInt(u16, std.builtin.Endian.little);

    const u16_max = std.math.maxInt(u16);
    var mem_instr_index = origin;
    reading: while (mem_instr_index < u16_max) {
        memory[mem_instr_index] = reader.readInt(u16, std.builtin.Endian.little) catch |err| {
            switch (err) {
                error.EndOfStream => break :reading,
                else => std.process.abort(),
            }
        };
        mem_instr_index += 1;
    }
}

fn read_image(image_path: [:0]const u8) !void {
    var file = try std.fs.cwd().openFile(image_path, .{});
    defer file.close();
    try read_image_file(file);
}

fn handle_interrupt(_: c_int) callconv(.C) void {
    restoreInputBuffering();
    const stdout = std.io.getStdOut().writer();
    var buffered_writer = std.io.bufferedWriter(stdout);
    const writer = buffered_writer.writer();
    writer.writeByte('\n') catch {};
    std.process.exit(2);
}

pub fn main() !void {
    _ = clib.signal(clib.SIGINT, handle_interrupt);
    disableInputBuffering();

    var args = std.process.args();
    _ = args.skip();
    const path = args.next() orelse {
        std.debug.print("Please provide a path for an image\n", .{});
        std.process.exit(1);
    };
    try read_image(path);

    Reg.COND.set(@intFromEnum(FLAG.ZRO));
    Reg.PC.set(PC_START);

    while (running) {
        const instr = mem_read(Reg.PC.get()) catch {
            std.log.warn("Failed to decode\n", .{});
            std.process.exit(5);
        };
        Reg.PC.add(1);
        try OP.handle_instruction(instr);
    }
}
