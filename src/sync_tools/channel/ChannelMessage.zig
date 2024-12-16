pub const SenderWarning = enum { ImClosed, NewSender };

pub fn ChannelMessage(comptime T: type) type {
    return union {
        const Self = @This();

        elt: T,
        sender_warning: SenderWarning,

        fn new(elt: T) Self {
            return Self{ .elt = elt };
        }

        fn new_warning(warn: SenderWarning) Self {
            return Self{ .sender_warning = warn };
        }
    };
}
