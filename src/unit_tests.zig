comptime {
    _ = @import("cpu/instructions.zig");
    _ = @import("cpu/utils.zig");
    _ = @import("cpu/Process.zig");
    _ = @import("cpu/Memory.zig");
    _ = @import("sync_tools/channel/ChannelQueue.zig");
    _ = @import("sync_tools/channel/Channel.zig");
}
