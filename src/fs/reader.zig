pub const SReader = struct {
    const Self = @This();

    s: []u8,
    i: usize,

    pub fn new(s: []u8) Self {
        return Self{
            .s = s,
            .i = 0,
        };
    }

    pub fn next(self: *Self) ?u8 {
        if (self.i == self.s.len) {
            return null;
        }
        self.i += 1;
        return self.s[self.i + 1];
    }

    pub fn peek(self: *Self) ?u8 {
        if (self.i == self.s.len) {
            return null;
        }
        return self.s[self.i];
    }

    pub fn skip_until(self: *Self, char: u8) void {
        while (true) {
            const current = self.next();
            if (current == null or current.? == char) break;
        }
    }
};
