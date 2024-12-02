const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_image.h");
    @cInclude("SDL_ttf.h");
});
const vec2 = @import("vec2.zig");
const Vec2 = vec2.Vec2;

const BASE_PADDING = 5;
const TERM_WIDTH = 80;
const TERM_HEIGHT = 60;
const TILE_SIZE = 15;

const HEIGHT = TERM_HEIGHT * TILE_SIZE;
const WIDTH = TERM_WIDTH * TILE_SIZE;

const NB_CHAR = 128;

const UI = struct {
    window: *sdl.SDL_Window,
    renderer: *sdl.SDL_Renderer,
    running: bool = true,
    cursor: Vec2,
    now: usize = 0,

    terminal: [WIDTH][HEIGHT]u8 = .{.{0} ** HEIGHT} ** WIDTH,
    font: [NB_CHAR]*sdl.SDL_Texture = .{undefined} ** NB_CHAR,

    fn destroy(self: *UI) void {
        sdl.SDL_DestroyRenderer(self.renderer);
        sdl.SDL_DestroyWindow(self.window);
    }

    fn write(self: *UI, char: u8) void {
        self.terminal[@intCast(self.cursor.x)][@intCast(self.cursor.y)] = char - 1;
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
        return Vec2.new(@intCast(i * TILE_SIZE + BASE_PADDING), @intCast(j * TILE_SIZE + BASE_PADDING));
    }

    fn display_cursor(self: *const UI) !void {
        _ = sdl.SDL_SetRenderDrawColor(self.renderer, 255, 255, 255, 255);
        const pos = Vec2.new(@intCast(self.cursor.x * TILE_SIZE + BASE_PADDING), @intCast(self.cursor.y * TILE_SIZE + BASE_PADDING / 2));
        const r = sdl.SDL_Rect{ .h = TILE_SIZE + 3, .w = TILE_SIZE, .x = pos.x, .y = pos.y };
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
                const r = sdl.SDL_Rect{ .h = TILE_SIZE, .w = TILE_SIZE, .x = pos.x, .y = pos.y };
                if (sdl.SDL_RenderCopy(self.renderer, self.font[c], null, &r) != 0) {
                    sdl.SDL_Log("Failed to display: %s", sdl.SDL_GetError());
                    return error.SDLInitializationFailed;
                }
            }
        }
        if (self.now % 40 < 20) try self.display_cursor();
    }
};

pub fn run() !void {
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

    var ui = UI{ .window = window, .renderer = renderer, .cursor = Vec2.zero() };
    defer ui.destroy();

    if (sdl.TTF_Init() != 0) {
        sdl.SDL_Log("Unable to init font: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    }

    const font = sdl.TTF_OpenFont("atwriter.ttf", 100) orelse {
        sdl.SDL_Log("Unable to open font: %s", sdl.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    sdl.TTF_SetFontStyle(font, sdl.TTF_STYLE_NORMAL);

    for (0..NB_CHAR) |i| {
        const surf: *sdl.SDL_Surface = sdl.TTF_RenderText_Blended(font, "1", sdl.SDL_Color{ .r = 0, .g = 0, .b = 0 }) orelse {
            sdl.SDL_Log("Unable to load letter: %d, %s", i, sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        ui.font[i] = sdl.SDL_CreateTextureFromSurface(renderer, surf) orelse {
            sdl.SDL_Log("Unable to create texture from surface for letter: %d, %s", i, sdl.SDL_GetError());
            return error.SDLInitializationFailed;
        };
        sdl.SDL_FreeSurface(surf);
    }

    var event: sdl.SDL_Event = undefined;
    while (ui.running) {
        while (sdl.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                sdl.SDL_QUIT => ui.running = false,
                sdl.SDL_KEYDOWN => ui.write(@intCast(event.key.keysym.scancode)),
                else => continue,
            }
        }
        try ui.display();
        sdl.SDL_RenderPresent(ui.renderer);
        _ = sdl.SDL_SetRenderDrawColor(ui.renderer, 0, 100, 0, 255);
        _ = sdl.SDL_RenderClear(ui.renderer);

        sdl.SDL_Delay(1000 / 60);
        ui.now += 1;
    }
}
