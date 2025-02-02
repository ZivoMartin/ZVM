const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL_ttf.h");
});
const KernelInterface = @import("../kernel/kernel.zig").KernelInterface;
const Ch = @import("../sync_tools/Channel.zig");

const parser = @import("parser.zig");
const command_evaluator = @import("command_evaluator.zig");

const vec2 = @import("vec2.zig");
const Vec2 = vec2.Vec2;

const PROMPT = "[ZVM >] ";
const LEFT_LIM = 0;

const BASE_PADDING = 5;
const TERM_WIDTH = 80;
const TERM_HEIGHT = 30;

const TILE_WIDTH = 20;
const TILE_HEIGHT = 30;

const HEIGHT = TERM_HEIGHT * TILE_HEIGHT;
const WIDTH = TERM_WIDTH * TILE_WIDTH;

const NB_CHAR = 173;

const Color = enum(u8) {
    Black = 0x0,
    Red = 0x1,

    fn get_sdl_color(self: Color) sdl.SDL_Color {
        return switch (self) {
            .Black => sdl.SDL_Color{ .r = 0, .g = 0, .b = 0 },
            .Red => sdl.SDL_Color{ .r = 180, .g = 0, .b = 0 },
        };
    }
};

const Square = struct {
    char: u8,
    writable: bool,
    color: Color,

    fn Default() Square {
        return Square{ .char = 0, .writable = true, .color = Color.Black };
    }
};

const Letter = struct {
    const NB_COLOR = @typeInfo(Color).@"enum".fields.len;

    colors: [NB_COLOR]?*sdl.SDL_Texture,

    fn new(font: ?*sdl.TTF_Font, renderer: ?*sdl.SDL_Renderer, l: u8) !Letter {
        const txt_arr: [2]u8 = .{ @intCast(l), 0 };
        const txt: [*c]const u8 = &txt_arr;

        var letter = Letter{ .colors = .{null} ** NB_COLOR };

        for (0..@typeInfo(Color).@"enum".fields.len) |i| {
            const color: Color = @enumFromInt(i);
            const surf: *sdl.SDL_Surface = sdl.TTF_RenderText_Blended(font, txt, color.get_sdl_color()) orelse {
                sdl.SDL_Log("Unable to load letter: %d, %s", l, sdl.SDL_GetError());
                return error.SDLInitializationFailed;
            };
            defer sdl.SDL_FreeSurface(surf);

            letter.colors[i] = sdl.SDL_CreateTextureFromSurface(renderer, surf) orelse {
                sdl.SDL_Log("Unable to create texture from surface for letter: %d, %s", l, sdl.SDL_GetError());
                return error.SDLInitializationFailed;
            };
        }
        return letter;
    }

    fn destroy(self: *const Letter) void {
        for (self.colors) |c| sdl.SDL_DestroyTexture(c);
    }

    fn get(self: Letter, color: Color) ?*sdl.SDL_Texture {
        return self.colors[@intFromEnum(color)];
    }
};

const UI = struct {
    window: *sdl.SDL_Window,
    renderer: *sdl.SDL_Renderer,
    running: bool,
    cursor: Vec2,
    now: usize,
    kernel: *KernelInterface,
    terminal: [WIDTH][HEIGHT]Square,
    font: [NB_CHAR]Letter,
    executable: bool,
    current_color: Color,
    mutex: std.Thread.Mutex,

    fn new(kernel: *KernelInterface) !*UI {
        if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO) != 0) {
            sdl.SDL_Log("Unable to initialize SDL: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        }
        const window = sdl.SDL_CreateWindow("My Game Window", sdl.SDL_WINDOWPOS_UNDEFINED, sdl.SDL_WINDOWPOS_UNDEFINED, WIDTH, HEIGHT, sdl.SDL_WINDOW_RESIZABLE) orelse {
            sdl.SDL_Log("Unable to create window: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        const renderer = sdl.SDL_CreateRenderer(window, -1, 0) orelse {
            sdl.SDL_Log("Unable to create renderer: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        };

        var ui = try kernel.allocator.create(UI);
        ui.kernel = kernel;
        ui.running = true;
        ui.now = 0;
        ui.window = window;
        ui.renderer = renderer;
        ui.cursor = Vec2.zero();
        ui.executable = true;
        ui.current_color = Color.Black;

        for (0..TERM_WIDTH) |i| {
            for (0..TERM_HEIGHT) |j|
                ui.terminal[i][j] = Square.Default();
        }

        try ui.init_font();

        ui.write_prompt();

        return ui;
    }

    fn init_font(self: *UI) !void {
        if (sdl.TTF_Init() != 0) {
            sdl.SDL_Log("Unable to init font: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        }

        const font = sdl.TTF_OpenFont("font.otf", 100) orelse {
            sdl.SDL_Log("Unable to open font: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        sdl.TTF_SetFontStyle(font, sdl.TTF_STYLE_NORMAL);

        for (1..NB_CHAR) |i| {
            self.font[i] = try Letter.new(font, self.renderer, @intCast(i));
        }
        sdl.TTF_CloseFont(font);
    }

    fn destroy(self: *UI) void {
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
        for (self.font[1..]) |letter| letter.destroy();
    }

    fn execute_command(self: *UI) !bool {
        const y: usize = @intCast(self.cursor.y);
        var len: usize = 0;
        var ind: usize = 0;
        while (ind < TERM_WIDTH and self.terminal[ind][y].char != 0) : (ind += 1) {
            if (self.terminal[ind][y].writable) len += 1;
        }
        const line = try self.kernel.allocator.alloc(u8, len);
        defer self.kernel.allocator.free(line);
        var j: usize = 0;
        for (0..TILE_WIDTH) |i| {
            if (j == len) break;
            if (self.terminal[i][y].writable) {
                line[j] = self.terminal[i][y].char;
                j += 1;
            }
        }
        const tree = try parser.parse(&self.kernel.allocator, &line);
        defer tree.destroy(&self.kernel.allocator);
        tree.display();
        if (!tree.is_empty()) {
            try command_evaluator.evaluate(self.kernel, tree);
            self.executable = false;
        }
        return tree.is_empty();
    }

    fn ret(self: *UI) !void {
        const write_p = self.executable and try self.execute_command();
        if (self.cursor.y != TERM_HEIGHT - 1) {
            self.cursor = Vec2.new(0, self.cursor.y + 1);
        } else {
            for (1..TERM_HEIGHT) |j| {
                for (0..TERM_WIDTH) |i| {
                    self.terminal[i][j - 1] = self.terminal[i][j];
                }
            }
            for (0..TERM_WIDTH) |i| {
                self.terminal[i][TERM_HEIGHT - 1] = Square.Default();
            }
            self.cursor.x = 0;
        }
        if (write_p) self.write_prompt();
    }

    fn del(self: *UI) void {
        if (self.cursor.x == 0 or !self.terminal[@intCast(self.cursor.x - 1)][@intCast(self.cursor.y)].writable) return;
        self.terminal[@intCast(self.cursor.x - 1)][@intCast(self.cursor.y)].char = 0;
        self.move_cursor_left();
    }

    fn write(self: *UI, char: u8) !void {
        if (char >= NB_CHAR or char == 0) return;
        switch (char) {
            '\n' => {
                try self.ret();
            },
            else => {
                self.terminal[@intCast(self.cursor.x)][@intCast(self.cursor.y)].char = char;
                self.terminal[@intCast(self.cursor.x)][@intCast(self.cursor.y)].color = self.current_color;
                self.move_cursor_right();
            },
        }
    }

    fn write_prompt(self: *UI) void {
        self.write_string(PROMPT) catch {
            std.debug.print("WARNING: FAILED TO WRITE PROMPT\n", .{});
            return;
        };
        for (0..PROMPT.len) |i| self.terminal[i][@intCast(self.cursor.y)].writable = false;
    }

    fn write_string(self: *UI, s: []const u8) !void {
        for (s) |c| try self.write(c);
    }

    fn move_cursor_left(self: *UI) void {
        if (self.cursor.x > 0) self.cursor.x -= 1;
    }

    fn move_cursor_right(self: *UI) void {
        if (self.cursor.x < TERM_WIDTH) self.cursor.x += 1;
    }

    fn get_terminal_position(i: usize, j: usize) Vec2 {
        return Vec2.new(@intCast(i * TILE_WIDTH + BASE_PADDING), @intCast(j * TILE_HEIGHT + BASE_PADDING));
    }

    fn display_cursor(self: *const UI) !void {
        _ = sdl.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 255);
        const pos = Vec2.new(@intCast(self.cursor.x * TILE_WIDTH + BASE_PADDING), @intCast(self.cursor.y * TILE_HEIGHT + BASE_PADDING / 2));
        const r = sdl.SDL_Rect{ .h = TILE_HEIGHT + 3, .w = TILE_WIDTH, .x = pos.x, .y = pos.y };
        _ = sdl.SDL_RenderFillRect(self.renderer, &r);
        if (sdl.SDL_RenderDrawRect(self.renderer, &r) != 0) {
            sdl.SDL_Log("Failed to display cursor: %s", sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        }
    }

    fn display(self: *UI) !void {
        self.mutex.lock();

        defer self.mutex.unlock();

        for (0..TERM_WIDTH) |i| {
            for (0..TERM_HEIGHT) |j| {
                const c = self.terminal[i][j];
                if (c.char == 0) continue;
                const pos = get_terminal_position(i, j);
                const r = sdl.SDL_Rect{ .h = TILE_HEIGHT, .w = TILE_WIDTH, .x = pos.x, .y = pos.y };
                if (sdl.SDL_RenderCopy(self.renderer, self.font[c.char].get(c.color), null, &r) != 0) {
                    sdl.SDL_Log("Failed to display: %s", sdl.SDL_GetError());
                    return error.SDLInitializationFailed;
                }
            }
        }
        if (self.now % 1600 < 800) try self.display_cursor();
    }

    fn handle_event(self: *UI, event: *sdl.SDL_Event) !void {
        switch (event.type) {
            sdl.SDL_QUIT => self.running = false,
            sdl.SDL_TEXTINPUT => try self.write(@intCast(event.text.text[0])),
            sdl.SDL_KEYDOWN => {
                switch (event.key.keysym.sym) {
                    sdl.SDLK_BACKSPACE => self.del(),
                    sdl.SDLK_RETURN => try self.ret(),
                    else => {},
                }
            },
            else => {},
        }
    }
};

pub const ShellMessage = struct {
    alloc: std.mem.Allocator,
    content: union(enum) {
        Stdout: []const u8,
        Stderr: []const u8,
        ProcessEnded: u1,
    },

    pub fn newStdout(alloc: std.mem.Allocator, content: []const u8) !*ShellMessage {
        const self = try alloc.create(ShellMessage);
        self.alloc = alloc;
        self.content = .{ .Stdout = content };
        return self;
    }

    pub fn newStderr(alloc: std.mem.Allocator, content: []const u8) !*ShellMessage {
        const self = try alloc.create(ShellMessage);
        self.alloc = alloc;
        self.content = .{ .Stderr = content };
        return self;
    }

    pub fn newProcessEnded(alloc: std.mem.Allocator) !*ShellMessage {
        const self = try alloc.create(ShellMessage);
        self.alloc = alloc;
        self.content = .{ .ProcessEnded = 1 };
        return self;
    }
};

pub const ShellSender = Ch.Sender(*ShellMessage, 100);

pub fn shell_messages_receiver(ui: *UI) !void {
    const channel = try Ch.Channel(*ShellMessage, 100).init(ui.kernel.allocator);
    try ui.kernel.give_shell_sender(channel.sender);
    while (true) {
        const msg = channel.receiver.recv() catch {
            break;
        };
        ui.mutex.lock();
        defer ui.mutex.unlock();
        switch (msg.content) {
            .Stdout => |s| {
                try ui.write_string(s);
            },
            .Stderr => |s| {
                ui.current_color = Color.Red;
                try ui.write_string(s);
                ui.current_color = Color.Black;
            },
            .ProcessEnded => |_| {
                ui.write_prompt();
                ui.executable = true;
            },
        }
    }
}

pub fn run(kernel: *KernelInterface) !void {
    var ui = try UI.new(kernel);
    defer ui.destroy();
    _ = try std.Thread.spawn(.{}, shell_messages_receiver, .{ui});

    var event: sdl.SDL_Event = undefined;
    while (ui.running) {
        while (sdl.SDL_PollEvent(&event) != 0) try ui.handle_event(&event);
        try ui.display();
        sdl.SDL_RenderPresent(ui.renderer);
        _ = sdl.SDL_SetRenderDrawColor(ui.renderer, 0, 100, 0, 255);
        _ = sdl.SDL_RenderClear(ui.renderer);
        ui.now += 1;
        _ = sdl.SDL_GetTicks();
    }
}
