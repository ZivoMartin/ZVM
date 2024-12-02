const memory = @import("memory.zig");
const utils = @import("utils.zig");
const image_reader = @import("image_reader.zig");
const registers = @import("registers.zig");
const Reg = registers.Reg;

pub const TR = enum(u16) {
    GETC = 0x20, //  get character from keyboard, not echoed onto the terminal
    OUT = 0x21, //  output a character
    PUTS = 0x22, //  output a word string
    IN = 0x23, //  get character from keyboard, echoed onto the terminal
    PUTSP = 0x24, //  output a byte string
    HALT = 0x25, //  halt the program

    pub fn process(self: TR) !void {
        switch (self) {
            .GETC => {
                const c = try utils.stdin.reader().readByte();
                Reg.R0.set(@as(u16, c));
                Reg.R0.update_flags();
            },
            .OUT => {
                const c: u8 = @truncate(Reg.R0.get());
                try utils.stdout.writer().writeByte(c);
            },
            .PUTS => {
                var addr = Reg.R0.get();
                while (true) : (addr += 1) {
                    const c = try memory.read(addr);
                    if (c == 0) {
                        break;
                    }
                    try utils.stdout.writer().writeByte(@truncate(c));
                }
            },
            .IN => {
                try utils.stdout.writer().writeAll("> ");
                try TR.OUT.process();
                try utils.stdout.writer().writeByte(@truncate(Reg.R0.get()));
            },
            .PUTSP => {
                var addr = Reg.R0.get();
                while (true) : (addr += 1) {
                    const cs = try memory.read(addr);
                    if (cs == 0) break;
                    const c1 = cs & 0xFF;
                    const c2 = cs >> 8;
                    try utils.stdout.writer().writeByte(@truncate(c1));
                    if (c2 != 0) {
                        try utils.stdout.writer().writeByte(@truncate(c2));
                    }
                }
            },
            .HALT => {
                try utils.stdout.writer().writeAll("End of processing\n");
                utils.restoreInputBuffering();
                image_reader.running = false;
            },
        }
    }
};
