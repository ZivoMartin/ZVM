const std = @import("std");
const uni = @cImport({
    @cInclude("unicorn/unicorn.h");
});

const MEMORY_ADDRESS: u32 = 0x1000;
const MEMORY_SIZE = 0x8000;
var memory: [MEMORY_SIZE]u8 = undefined;

pub fn read_image(path: [:0]const u8) !void {
    const bytes_loaded = try inject_image(path);

    var uc: ?*uni.uc_engine = undefined;

    var err = uni.uc_open(uni.UC_ARCH_X86, uni.UC_MODE_64, &uc);
    if (err != uni.UC_ERR_OK) {
        std.debug.print("Unicorn init error: {s}\n", .{uni.uc_strerror(err)});
        return;
    }

    err = uni.uc_mem_map(uc, MEMORY_ADDRESS, MEMORY_SIZE, uni.UC_PROT_ALL);
    if (err != uni.UC_ERR_OK) {
        std.debug.print("Memory mapping failed: {s}\n", .{uni.uc_strerror(err)});
        return;
    }

    err = uni.uc_mem_write(uc, MEMORY_ADDRESS, &memory, bytes_loaded);
    if (err != uni.UC_ERR_OK) {
        std.debug.print("Memory write failed: {s}\n", .{uni.uc_strerror(err)});
        return;
    }

    var hook: uni.uc_hook = undefined;
    err = uni.uc_hook_add(uc, &hook, uni.UC_HOOK_INTR, @constCast(@ptrCast(&hook_intr)), null, 1, 0);
    if (err != uni.UC_ERR_OK) {
        std.debug.print("Hook add failed: {s}\n", .{uni.uc_strerror(err)});
        return;
    }

    err = uni.uc_reg_write(uc, uni.UC_X86_REG_RIP, &MEMORY_ADDRESS);
    var x: i32 = undefined;
    _ = uni.uc_reg_read(uc, uni.UC_X86_REG_RIP, &x);
    std.debug.print("{} {} {}\n", .{ x, bytes_loaded, MEMORY_SIZE });

    if (err != uni.UC_ERR_OK) {
        std.debug.print("Init PC failed: {s}\n", .{uni.uc_strerror(err)});
        return;
    }

    err = uni.uc_emu_start(uc, MEMORY_ADDRESS, MEMORY_ADDRESS + bytes_loaded - 1, 0, 0);

    x = undefined;
    _ = uni.uc_reg_read(uc, uni.UC_X86_REG_RIP, &x);
    std.debug.print("{}\n", .{x});

    if (err != uni.UC_ERR_OK) {
        std.debug.print("Execution failed: {s}\n", .{uni.uc_strerror(err)});
        return;
    }

    _ = uni.uc_close(uc);
}

fn inject_image(image_path: [:0]const u8) !usize {
    const file = try std.fs.cwd().openFile(image_path, .{});
    defer file.close();

    const bytes_read = try file.readAll(&memory);
    return bytes_read;
}

fn hook_intr(_: *uni.uc_engine, intno: u32, _: ?*anyopaque) void {
    std.debug.print("Interrupt {d} encountered\n", .{intno});
}
