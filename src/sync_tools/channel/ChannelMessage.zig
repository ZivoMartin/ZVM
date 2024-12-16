pub const SenderWarning = enum { ImClosed, NewSender };

pub fn ChannelMessage(comptime T: type) type {
    return union(enum) {
        const Self = @This();

        elt: T,
        sender_warning: SenderWarning,

        pub fn new(elt: T) Self {
            return Self{ .elt = elt };
        }

        pub fn new_warning(warn: SenderWarning) Self {
            return Self{ .sender_warning = warn };
        }
    };
}
