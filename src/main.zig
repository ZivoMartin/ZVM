const std = @import("std");
const File = std.fs.File;
const linux = std.os.linux;
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

    var reg: [@typeInfo(Reg).@"enum".fields.len]u16 = undefined;

    pub fn set(self: Reg, val: u16) void {
        reg[@intFromEnum(self)] = val;
    }

    pub fn get(self: Reg) u16 {
        return reg[@intFromEnum(self)];
    }

    pub fn add(self: Reg, x: u16) void {
        self.set(self.get() +% x);
    }

    fn update_flags(self: Reg) void {
        const val = self.get();
        if (val == 0) {
            Reg.COND.set(@intFromEnum(FLAG.ZRO));
        } else if (val >> 15 == 1) {
            Reg.COND.set(@intFromEnum(FLAG.NEG));
        } else {
            Reg.COND.set(@intFromEnum(FLAG.POS));
        }
    }
};

const stdin = std.io.getStdIn();
const stdout = std.io.getStdOut();

const TR = enum(u16) {
    GETC = 0x20, //  get character from keyboard, not echoed onto the terminal
    OUT = 0x21, //  output a character
    PUTS = 0x22, //  output a word string
    IN = 0x23, //  get character from keyboard, echoed onto the terminal
    PUTSP = 0x24, //  output a byte string
    HALT = 0x25, //  halt the program

    fn process(self: TR) !void {
        switch (self) {
            .GETC => {
                const c = try stdin.reader().readByte();
                Reg.R0.set(@as(u16, c));
                Reg.R0.update_flags();
            },
            .OUT => {
                const c: u8 = @truncate(Reg.R0.get());
                try stdout.writer().writeByte(c);
            },
            .PUTS => {
                var addr = Reg.R0.get();
                while (true) : (addr += 1) {
                    const c = try mem_read(addr);
                    if (c == 0) {
                        break;
                    }
                    try stdout.writer().writeByte(@truncate(c));
                }
            },
            .IN => {
                try stdout.writer().writeAll("> ");
                try TR.OUT.process();
                try stdout.writer().writeByte(@truncate(Reg.R0.get()));
            },
            .PUTSP => {
                var addr = Reg.R0.get();
                while (true) : (addr += 1) {
                    const cs = try mem_read(addr);
                    if (cs == 0) break;
                    const c1 = cs & 0xFF;
                    const c2 = cs >> 8;
                    try stdout.writer().writeByte(@truncate(c1));
                    if (c2 != 0) {
                        try stdout.writer().writeByte(@truncate(c2));
                    }
                }
            },
            .HALT => {
                try stdout.writer().writeAll("End of processing");
                restoreInputBuffering();
                running = false;
            },
        }
    }
};

fn sign_extend(num: u16, comptime og_bits: u4) u16 {
    if (og_bits == 0) {
        return 0;
    }
    const shift = 16 - @as(u16, og_bits);
    return @bitCast(@as(i16, @bitCast(num << shift)) >> shift);
}

const OP = enum(u8) {
    BR,
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
        const op: OP = @enumFromInt(instr >> 12);
        switch (op) {
            .BR => {
                const cond_flag = (instr >> 9) & 0x7;
                if ((cond_flag & Reg.COND.get()) != 0) {
                    const pc_offset = sign_extend(instr & 0x1FF, 9);
                    Reg.PC.add(pc_offset);
                }
            },
            .ADD => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const imm_flag = (instr >> 5) & 0x1;
                if (imm_flag != 0) {
                    const imm5 = sign_extend(instr & 0x1F, 5);
                    r0.set(r1.get() +% imm5);
                } else {
                    const r2: Reg = @enumFromInt(instr & 0x7);
                    r0.set(r1.get() +% r2.get());
                }
                r0.update_flags();
            },
            .LD => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                r0.set(try mem_read(Reg.PC.get() +% pc_offset));
                r0.update_flags();
            },
            .ST => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                mem_write(Reg.PC.get() +% pc_offset, r0.get());
            },
            .JSR => {
                const long_flag = (instr >> 11) & 0x1;
                Reg.R7.set(Reg.PC.get());
                if (long_flag != 0) {
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
                if (imm_flag != 0) {
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
                r0.set(try mem_read(r1.get() +% offset));
                r0.update_flags();
            },
            .STR => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                const offset = sign_extend((instr & 0x3F), 6);
                mem_write(r1.get() +% offset, r0.get());
            },
            .RTI => {
                std.debug.print("The RTI instruction is not supported.", .{});
                std.process.exit(1);
            },
            .NOT => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const r1: Reg = @enumFromInt((instr >> 6) & 0x7);
                r0.set(~r1.get());
                r0.update_flags();
            },
            .LDI => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                r0.set(try mem_read(try mem_read(Reg.PC.get() +% pc_offset)));
                r0.update_flags();
            },
            .STI => {
                const r0: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = sign_extend(instr & 0x1FF, 9);
                mem_write(try mem_read(Reg.PC.get() +% pc_offset), r0.get());
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
                r0.set(Reg.PC.get() +% pc_offset);
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
    var fds = [_]linux.pollfd{.{ .fd = linux.STDIN_FILENO, .events = linux.POLL.IN, .revents = 0 }};
    const reported_events = linux.poll(&fds, fds.len, 0);
    return reported_events > 0 and (fds[0].revents & linux.POLL.IN) != 0;
}

var og_termios: linux.termios = undefined;

pub fn disableCanonAndEcho() void {
    _ = linux.tcgetattr(linux.STDIN_FILENO, &og_termios);
    var new_termios = og_termios;
    new_termios.lflag.ICANON = false;
    new_termios.lflag.ECHO = false;
    _ = linux.tcsetattr(linux.STDIN_FILENO, linux.TCSA.NOW, &new_termios);
}
fn restoreInputBuffering() void {
    _ = linux.tcsetattr(linux.STDIN_FILENO, linux.TCSA.NOW, &og_termios);
}

fn mem_read(i: u16) !u16 {
    if (i == @intFromEnum(MR.KBSR)) {
        if (check_key()) {
            memory[@intFromEnum(MR.KBSR)] = 1 << 15;
            memory[@intFromEnum(MR.KBDR)] = std.io.getStdIn().reader().readByte() catch memory[@intFromEnum(MR.KBDR)];
        } else {
            memory[@intFromEnum(MR.KBSR)] = 0;
        }
    }
    return memory[i];
}

fn mem_write(i: u16, x: u16) void {
    memory[i] = x;
}

fn getProgramOrigin(file: std.fs.File) !u16 {
    var buffer: [2]u8 = undefined;
    const bytes_read = try file.read(&buffer);
    if (bytes_read < buffer.len) {
        return error.InsufficientData;
    }
    return std.mem.readInt(u16, &buffer, .big);
}

fn read_image(image_path: [:0]const u8) !void {
    const file = try std.fs.cwd().openFile(image_path, .{});
    defer file.close();
    const origin = try getProgramOrigin(file);
    var buffer: [2]u8 = undefined;
    var index = origin;
    while (true) : (index += 1) {
        const bytes_read = try file.read(&buffer);
        if (bytes_read < buffer.len or index >= MEMORY_MAX) break;
        memory[index] = std.mem.readInt(u16, &buffer, .big);
    }
}

fn handle_interrupt(_: c_int) callconv(.C) void {
    restoreInputBuffering();
    stdout.writer().writeByte('\n') catch {};
    std.process.exit(2);
}

var act = std.os.linux.Sigaction{
    .handler = .{ .handler = handle_interrupt },
    .mask = std.os.linux.empty_sigset,
    .flags = 0,
};

pub fn main() !void {
    _ = linux.sigaction(std.os.linux.SIG.INT, &act, null);
    _ = linux.sigaction(std.os.linux.SIG.TERM, &act, null);
    disableCanonAndEcho();

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
