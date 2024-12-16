const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL_ttf.h");
});
const KernelInterface = @import("../kernel/kernel.zig").KernelInterface;

const parser = @import("parser.zig");
const command_evaluator = @import("command_evaluator.zig");

const vec2 = @import("vec2.zig");
const Vec2 = vec2.Vec2;

const BASE_PADDING = 5;
const TERM_WIDTH = 80;
const TERM_HEIGHT = 30;

const TILE_WIDTH = 20;
const TILE_HEIGHT = 30;

const HEIGHT = TERM_HEIGHT * TILE_HEIGHT;
const WIDTH = TERM_WIDTH * TILE_WIDTH;

const NB_CHAR = 173;

const UI = struct {
    window: *sdl.SDL_Window,
    renderer: *sdl.SDL_Renderer,
    running: bool,
    cursor: Vec2,
    now: usize,
    kernel: *KernelInterface,
    terminal: [WIDTH][HEIGHT]u8,
    font: [NB_CHAR]*sdl.SDL_Texture,

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
        for (0..TERM_WIDTH) |i| {
            for (0..TERM_HEIGHT) |j| ui.terminal[i][j] = 0;
        }

        try ui.init_font();

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
            const txt_arr: [2]u8 = .{ @intCast(i), 0 };
            const txt: [*c]const u8 = &txt_arr;
            const surf: *sdl.SDL_Surface = sdl.TTF_RenderText_Blended(font, txt, sdl.SDL_Color{ .r = 0, .g = 0, .b = 0 }) orelse {
                sdl.SDL_Log("Unable to load letter: %d, %s", i, sdl.SDL_GetError());
                return error.SDLInitializationFailed;
            };
            self.font[i] = sdl.SDL_CreateTextureFromSurface(self.renderer, surf) orelse {
                sdl.SDL_Log("Unable to create texture from surface for letter: %d, %s", i, sdl.SDL_GetError());
                return error.SDLInitializationFailed;
            };
            sdl.SDL_FreeSurface(surf);
        }
    }

    fn destroy(self: *UI) void {
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
        for (self.font[1..]) |letter| sdl.SDL_DestroyTexture(letter);
    }

    fn execute_command(self: *UI) !void {
        const y: usize = @intCast(self.cursor.y);
        var len: usize = 0;
        while (len < TERM_WIDTH and self.terminal[len][y] != 0) : (len += 1) {}
        const line = try self.kernel.allocator.alloc(u8, len);
        defer self.kernel.allocator.free(line);
        for (0..len) |i| line[i] = self.terminal[i][y];
        const tree = try parser.parse(&self.kernel.allocator, &line);
        defer tree.destroy(&self.kernel.allocator);
        tree.display();
        try command_evaluator.evaluate(self.kernel, tree);
    }

    fn ret(self: *UI) !void {
        try self.execute_command();
        if (self.cursor.y != TERM_HEIGHT - 1) {
            self.cursor = Vec2.new(0, self.cursor.y + 1);
        } else {
            for (1..TERM_HEIGHT) |j| {
                for (0..TERM_WIDTH) |i| {
                    self.terminal[i][j - 1] = self.terminal[i][j];
                }
            }
            for (0..TERM_WIDTH) |i| {
                self.terminal[i][TERM_HEIGHT - 1] = 0;
            }
            self.cursor.x = 0;
        }
    }

    fn del(self: *UI) void {
        if (self.cursor.x == 0) return;
        self.terminal[@intCast(self.cursor.x - 1)][@intCast(self.cursor.y)] = 0;
        self.move_cursor_left();
    }

    fn write(self: *UI, char: u8) void {
        if (char >= NB_CHAR) return;
        self.terminal[@intCast(self.cursor.x)][@intCast(self.cursor.y)] = char;
        self.move_cursor_right();
    }

    fn write_string(self: *UI, s: []u8) void {
        for (s) |c| self.write(c);
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

    fn display(self: *const UI) !void {
        for (self.terminal, 0..) |line, i| {
            for (line, 0..) |c, j| {
                if (c == 0) continue;
                const pos = get_terminal_position(i, j);
                const r = sdl.SDL_Rect{ .h = TILE_HEIGHT, .w = TILE_WIDTH, .x = pos.x, .y = pos.y };
                if (sdl.SDL_RenderCopy(self.renderer, self.font[c], null, &r) != 0) {
                    sdl.SDL_Log("Failed to display: %s", sdl.SDL_GetError());
                    return error.SDLInitializationFailed;
                }
            }
        }
        if (self.now % 40 < 20) try self.display_cursor();
    }

    fn handle_event(self: *UI, event: *sdl.SDL_Event) !void {
        switch (event.type) {
            sdl.SDL_QUIT => self.running = false,
            sdl.SDL_TEXTINPUT => self.write(@intCast(event.text.text[0])),
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

pub fn run(kernel: *KernelInterface) !void {
    var ui = try UI.new(kernel);
    defer ui.destroy();

    var event: sdl.SDL_Event = undefined;
    while (ui.running) {
        while (sdl.SDL_PollEvent(&event) != 0) try ui.handle_event(&event);
        try ui.display();
        sdl.SDL_RenderPresent(ui.renderer);
        _ = sdl.SDL_SetRenderDrawColor(ui.renderer, 0, 100, 0, 255);
        _ = sdl.SDL_RenderClear(ui.renderer);

        _ = sdl.SDL_GetTicks();

        ui.now += 1;
    }
}
