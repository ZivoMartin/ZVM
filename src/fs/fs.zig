/// This file handle the interaction with the ZVM file system. The whole fs is stored in the ($HOME)/.zvmfs file of your system, the file starts with the interface loaded by the FS interface to catch all the files datas. Then, from the end of the files starts the file's content. Thus, we can easly add some files and modify the interface part of the fs without having some issue with the file's content. The fs contains FS_SIZE bytes.
/// This is the interface fs part file definition paterns, first we have folders, prefixed with F, we simply indicates the folder name followed with { and } delimiting the begining and endof the folder. Note that each special charcter is prefixed with \ when it has to be interpreted as a normal character and the '\' char itself is prefixed with \. For the files, prefixed with f, havind this form: file_name:file_addr. Note that the root folder doesn't have to be named.
const std = @import("std");
const FS_SIZE = 10_000_000;

const FS_PATH = "/home/martin/.zvmfs";

const BASE_FS = "fp1:0fp2:12f\\f2:235";

const FileInterface = struct {};

const FolderInterface = struct {};

pub fn u32_bytes(x: u32) [4]u8 {
    return .{
        @truncate(x >> 24),
        @truncate(x >> 16 & 0xFF),
        @truncate(x >> 8 & 0xFF),
        @truncate(x & 0xFF),
    };
}

pub fn read_u32(buff: [4]u8) u32 {
    return (@as(u32, buff[0]) << 24) |
        (@as(u32, buff[1]) << 16) |
        (@as(u32, buff[2]) << 8) |
        @as(u32, buff[3]);
}

pub const FS = struct {
    files: std.AutoHashMap([]u8, usize),
    root: *FolderInterface,
    fs: std.fs.File,
    alloc: std.mem.Allocator,

    /// This function creates the .zvmfs file and fill it with 0. The file will contains FS_SIZE zero after calling this function
    fn mount() !std.fs.File {
        const fs = try std.fs.cwd().createFile(
            FS_PATH,
            .{ .read = true },
        );
        const writer = fs.writer();
        for (0..FS_SIZE) |_| {
            try writer.writeByte(0);
        }
        try inject_base_files(fs);
        return fs;
    }

    fn inject_base_files(fs: std.fs.File) !void {
        try fs.writeAll(&u32_bytes(BASE_FS.len));
        try fs.writeAll(BASE_FS); // This juste creates 3 randoms file
    }

    fn read_next_file(_: *std.io.Reader, _: *const std.mem.Allocator) !void {}

    fn init(_: std.mem.Allocator) !void {
        const f: std.fs.File = std.fs.cwd().openFile(FS_PATH, .{ .mode = .read_write }) catch try mount();
        // try inject_base_files(f);
        var buffer: [4]u8 = undefined;
        const reader = f.reader();
        _ = try reader.readAll(&buffer);
        std.debug.print("{}\n", .{read_u32(buffer)});
    }

    fn deinit(self: *FS, alloc: std.mem.Allocator) void {
        self.fs.close();
        alloc.destroy(self);
        self.* = undefined;
    }
};

test "fs creation" {
    const test_allocator = std.testing.allocator;

    try FS.init(test_allocator);
}
