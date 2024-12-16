comptime {
    _ = @import("cpu/instructions.zig");
    _ = @import("cpu/utils.zig");
    _ = @import("cpu/process.zig");
    _ = @import("cpu/memory.zig");
    _ = @import("sync_tools/channel/ChannelQueue.zig");
}
