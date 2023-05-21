const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const BOMB_NUMBER = 25;

const BOARD_W = 10;
const BOARD_H = 10;

const SCREEN_W = 1280;
const SCREEN_H = 720;

const TILE_W: i32 = SCREEN_W / BOARD_W;
const TILE_H: i32 = SCREEN_H / BOARD_H;
const TILE_PADDING = 2;

const Tile = struct {
    revealed: bool,
    flagged: bool,
    isBomb: bool,
    value: u4,
};

const Allocator = std.mem.Allocator;

fn contains_vec(haystack: []const @Vector(2, usize), needle: @Vector(2, usize)) bool {
    var i: usize = 0;
    while (i < haystack.len) : (i += 1) {
        const chk = haystack[i] == needle;
        if (chk[0] and chk[1]) return true;
    }
    return false;
}


const Board = struct {
    const Self = @This();
    tiles: [BOARD_W][BOARD_H]Tile,
    bombsRemaining: u16,
    pub fn init(allocator: Allocator, bombNumber: u16) !Board {
        var board: Board = undefined;
        const seed = 0;
        var prng = std.rand.DefaultPrng.init(seed);
        const rand = prng.random();
        const Pos = @Vector(2, usize);
        
        for (board.tiles) |ts, y| {
            for (ts) |_, x| {
                board.tiles[x][y] = .{
                    .isBomb = false,
                    .value = 0,
                    .revealed = false,
                    .flagged = false
                };
            }
        }

        var bombLocations: []Pos = try allocator.alloc(Pos, bombNumber);
        for (bombLocations) |_, i| {
            var vec = .{ 
                rand.intRangeAtMost(usize, 0, BOARD_W - 1),
                rand.intRangeAtMost(usize, 0, BOARD_H - 1)
            };
            while (contains_vec(bombLocations, vec)) {
                vec = .{ 
                    rand.intRangeAtMost(usize, 0, BOARD_W - 1),
                    rand.intRangeAtMost(usize, 0, BOARD_H - 1)
                };
            }
            bombLocations[i] = vec;
        }

        for (bombLocations) |loc| {
            board.tiles[loc[0]][loc[1]].isBomb = true;
            const x = loc[0];
            const y = loc[1];
            const positions = neighbor_pos(x, y);
            for (positions) |p| {
                if (p[0] < 0 or p[1] < 0 or p[0] >= BOARD_W or p[1] >= BOARD_H) continue;
                const px = @intCast(usize, p[0]);
                const py = @intCast(usize, p[1]);
                board.tiles[px][py].value += 1;
            }
        }
        board.bombsRemaining = bombNumber;
        return board;
    }
};

fn neighbor_pos(x: usize, y: usize) []@Vector(2, usize) {
    const xi = @intCast(i32, x);
    const yi = @intCast(i32, y);
    const vectors = [_]@Vector(2, i32) { 
        .{xi - 1, yi}, 
        .{xi + 1, yi},   
        .{xi, yi - 1},
        .{xi, yi + 1},
        .{xi - 1, yi - 1},
        .{xi - 1, yi + 1},
        .{xi + 1, yi - 1},
        .{xi + 1, yi + 1}
    };
    var counter: usize = 0;
    var result: [9]@Vector(2, usize) = undefined;
    for (vectors) |vec| {
        if (vec[0] < 0 or vec[0] >= BOARD_W or vec[1] < 0 or vec[1] >= BOARD_H) {
            continue;
        }
            result[counter] = .{
            @intCast(usize, vec[0]),
            @intCast(usize, vec[1])
        };
        counter += 1;
    }
    std.debug.print("neighbor: {any}\n", .{result[0..counter]});
    return result[0..counter];
}

const GameCtx = struct {
    tileTextures: [10]*c.SDL_Texture,
    flagTexture: *c.SDL_Texture,
    bombTexture: *c.SDL_Texture,
    board: Board,
    renderer: *c.SDL_Renderer,
    window: *c.SDL_Window,
    const Self = @This();
    pub fn init(allocator: Allocator) !Self {
        var ctx: Self = undefined;
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS) < 0) return error.SDLInitFailed;
        const window = c.SDL_CreateWindow(
            "uwu", 
            c.SDL_WINDOWPOS_UNDEFINED, 
            c.SDL_WINDOWPOS_UNDEFINED, 
            SCREEN_W, SCREEN_H, 0
        ).?;
        const renderer = c.SDL_CreateRenderer(
            window,
            -1,
            c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC
        ).?;

        ctx.window = window;
        ctx.renderer = renderer;
        var tileTextures: [10]*c.SDL_Texture = undefined;
        inline for (tileTextures) |_, i|  {
            const surface = c.SDL_LoadBMP(std.fmt.comptimePrint("res/tile{}.bmp", .{i}));
            defer c.SDL_FreeSurface(surface);
            tileTextures[i] = c.SDL_CreateTextureFromSurface(renderer, surface).?;
        }
        ctx.tileTextures = tileTextures;

        const flagSurface = c.SDL_LoadBMP("res/flag.bmp");
        defer c.SDL_FreeSurface(flagSurface);
        ctx.flagTexture = c.SDL_CreateTextureFromSurface(renderer, flagSurface).?;

        const bombSurface = c.SDL_LoadBMP("res/bomb.bmp");
        defer c.SDL_FreeSurface(bombSurface);
        ctx.bombTexture = c.SDL_CreateTextureFromSurface(renderer, bombSurface).?;

        ctx.board = try Board.init(allocator, BOMB_NUMBER);

        return ctx;
    }
    pub fn deinit(self: *Self) void {
        c.SDL_Quit();
        c.SDL_DestroyWindow(self.window);
        c.SDL_DestroyRenderer(self.renderer);
        for (self.tileTextures) |t| {
            c.SDL_DestroyTexture(t);
        }
        c.SDL_DestroyTexture(self.flagTexture);
        c.SDL_DestroyTexture(self.bombTexture);
    }
    pub fn render(self: *Self) void {
        _ = c.SDL_SetRenderDrawColor(self.renderer, 0xFF, 0xFF, 0xFF, 0xFF);
        _ = c.SDL_RenderClear(self.renderer);
        for (self.board.tiles) |ts, y| {
            for (ts) |t, x| {
                
                const img = switch (t.revealed) {
                    true => switch (t.isBomb) {
                        true => self.bombTexture,
                        false => self.tileTextures[t.value]
                    },
                    false => switch (t.flagged) {
                        true => self.flagTexture,
                        false => continue,
                    }
                };
                const rect = c.SDL_Rect {
                    .x = TILE_W * @intCast(c_int, x),
                    .y = TILE_H * @intCast(c_int, y),
                    .w = TILE_W - TILE_PADDING,
                    .h = TILE_H - TILE_PADDING
                };
                _ = c.SDL_RenderCopy(self.renderer, img, null, &rect);
            }
        }
        _ = c.SDL_RenderPresent(self.renderer);
    }
    pub fn left_click(self: *Self, pos: @Vector(2, usize)) bool {
        const tile = &self.board.tiles[pos[0]][pos[1]];
        if (tile.isBomb) return true;
        switch (tile.revealed) {
            false => {
                tile.revealed = true;
                std.debug.print("pos: {any}\n", .{pos});
                const neighbors: []@Vector(2, usize) = neighbor_pos(pos[0], pos[1]);
                std.debug.print("left: {any}\n", .{neighbors});
                for (neighbors) |neighbor| {
                    const ntile = self.board.tiles[neighbor[0]][neighbor[1]];
                    if (ntile.revealed or ntile.isBomb) continue;
                    if (ntile.value == 0) {
                       _ = self.left_click(neighbor);
                    }
                }
            },
            // TODO: do the auto reveal thing
            true => {},
        }
        return false;
    }
    pub fn right_click(self: *Self, pos: @Vector(2, usize)) void {
        const tile = &self.board.tiles[pos[0]][pos[1]];
        switch (tile.revealed) {
            false => tile.flagged = !tile.flagged,
            // TODO: do the auto flag thing
            true => {},
        }
    }
};

fn coord_to_pos(x: u32, y: u32) @Vector(2, usize) {
    return .{ 
        y / @intCast(u32, TILE_H - TILE_PADDING),
        x / @intCast(u32, TILE_W - TILE_PADDING)
    };
}

pub fn main() !void {
    var quit = false;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var ctx = try GameCtx.init(allocator);
    defer ctx.deinit();
        while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.@"type") {
                c.SDL_QUIT => quit = true,
                c.SDL_MOUSEBUTTONUP => {
                    switch (event.button.button) {
                        c.SDL_BUTTON_LEFT => {
                            const x = @intCast(u32, event.button.x);
                            const y = @intCast(u32, event.button.y);
                            const pos = coord_to_pos(x, y);
                            if (ctx.left_click(pos)) quit = true;
                        },
                        c.SDL_BUTTON_RIGHT => {
                            const x = @intCast(u32, event.button.x);
                            const y = @intCast(u32, event.button.y);
                            const pos = coord_to_pos(x, y);
                            ctx.right_click(pos);
                         },
                        else  => {}
                    }
                },
                else => {}
            }
        }
        ctx.render();
    }
}
