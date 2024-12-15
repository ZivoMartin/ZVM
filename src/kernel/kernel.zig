const std = @import("std");
const Thread = std.Thread;

const Kernel = struct {};

pub const ProtectedKernel = struct { kernel: Kernel, mutex: Thread.Mutex };
