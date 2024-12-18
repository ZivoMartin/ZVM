/// This file handle the interaction with the ZVM file system. The whole fs is stored in the ($HOME)/.zvmfs file of your system, the file starts with the interface loaded by the FS interface to catch all the files datas. Then, from the end of the files starts the file's content. Thus, we can easly add some files and modify the interface part of the fs without having some issue with the file's content. The fs contains FS_SIZE bytes.
/// This is the interface fs part file definition paterns, first we have folders, prefixed with {, we simply indicates the folder name followed with { and } delimiting the begining and endof the folder. Note that each special charcter is prefixed with \ when it has to be interpreted as a normal character and the '\' char itself is prefixed with \. For the files, prefixed with f, havind this form: file_name:file_addr. Note that the root folder doesn't have to be named.
const std = @import("std");
const utils = @import("../utils.zig");
const SReader = @import("reader.zig").SReader;

const FS_SIZE = 10_000;

const FS_PATH = "/home/martin/.zvmfs";

const BASE_FS = "{fp1:0:fp2:12:f\\f2:235:}";

const FileInterface = struct {};

const FolderInterface = struct {};

const FS_Error = error{ InvalidInterfaceSize, FailedToReadInterfaceSize, FailedToInjectInterface, InvalidItemDescriptorChar, UnexpectedEOF };

pub const FS = struct {
    const Self = @This();

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
        const interface_size = BASE_FS.len + 4;
        var buffer = [_]u8{0} ** (interface_size);
        utils.write_u32_bytes(buffer[0..4], BASE_FS.len);
        std.mem.copyForwards(u8, buffer[4..], BASE_FS);
        if (try fs.pwrite(&buffer, 0) != interface_size) {
            return FS_Error.FailedToInjectInterface;
        }
    }

    fn read_next_file(self: *Self, reader: *SReader) !void {}

    fn read_folder(self: *Self, reader: *SReader) !void {
        while (true) {
            const current = reader.next();
            if (current == null or current.? == '}') return;

            switch (current.?) {
                'f' => try self.read_next_file(&reader),
                '{' => try self.read_folder(&reader),
                else => return FS_Error.InvalidItemDescriptorChar,
            }
        }
    }

    fn get_fs_interface(alloc: *const std.mem.Allocator, f: std.fs.File) !SReader {
        var buffer: [4]u8 = undefined;
        const reader = f.reader();
        if (try reader.readAll(&buffer) != 4) {
            return FS_Error.FailedToReadInterfaceSize;
        }
        const interface_size = utils.read_u32(buffer);
        const res = try alloc.alloc(u8, interface_size);
        if (try reader.readAll(res) != interface_size) {
            return FS_Error.InvalidInterfaceSize;
        }
        return SReader.new(res);
    }

    fn init(alloc: std.mem.Allocator) !*Self {
        const self = try alloc.create(Self);

        // files: std.AutoHashMap([]u8, usize),
        // root: *FolderInterface,

        self.fs = std.fs.cwd().openFile(FS_PATH, .{ .mode = .read_write }) catch try mount();
        self.alloc = alloc;
        const interface = try get_fs_interface(&self.alloc, self.fs);
        defer self.alloc.free(interface.s);
        try self.read_folder(&interface);
        return self;
    }

    fn deinit(self: *FS) void {
        self.fs.close();
        self.alloc.destroy(self);
    }
};

test "fs creation" {
    const test_allocator = std.testing.allocator;

    const fs = try FS.init(test_allocator);
    defer fs.deinit();
}
