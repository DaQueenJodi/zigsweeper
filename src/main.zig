const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});


const Position = @Vector(2, usize);

const BOMB_NUMBER = 150;

const BOARD_W = 20;
const BOARD_H = 20;

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
    near: []@Vector(2, usize),
};

const Allocator = std.mem.Allocator;

fn contains_vec(comptime T: type, haystack: []const T, needle: T) bool {
    var i: usize = 0;
    while (i < haystack.len) : (i += 1) {
        const chk = haystack[i] == needle;
        if (chk[0] and chk[1]) return true;
    }
    return false;
}
fn all(vec: @Vector(2, bool)) bool {
    return (vec[0] and vec[1]);
}

const Board = struct {
    const Self = @This();
    tiles: [BOARD_W][BOARD_H]Tile,
    bombsRemaining: u16,
    pub fn init(allocator: Allocator, bombNumber: u16, firstClickPos: Position) !Board {
        var board: Board = undefined;
        const seed = @truncate(u64, @bitCast(u128, std.time.nanoTimestamp()));
        var prng = std.rand.DefaultPrng.init(seed);
        const rand = prng.random();

        for (board.tiles, 0..) |ts, y| {
            for (ts, 0..) |_, x| {
                board.tiles[x][y] = .{ 
                    .isBomb = false, 
                    .value = 0, 
                    .revealed = false, 
                    .flagged = false,
                    .near = try neighbor_pos(allocator, x, y)
                };
            }
        }
        var bombLocations: []Position = try allocator.alloc(Position, bombNumber);
        defer allocator.free(bombLocations);
        for (bombLocations, 0..) |_, i| {
            var vec = Position { 
                rand.intRangeAtMost(usize, 0, BOARD_W - 1), 
                rand.intRangeAtMost(usize, 0, BOARD_H - 1) 
            };
            const firstClickTile = &board.tiles[firstClickPos[0]][firstClickPos[1]];
            while (
                contains_vec(Position, bombLocations, vec) or
                contains_vec(Position, firstClickTile.near, vec) or
                all(firstClickPos == vec)
                ) {
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
            const positions = board.tiles[x][y].near;
            for (positions) |p| {
                const px = p[0];
                const py = p[1];
                board.tiles[px][py].value += 1;
            }
        }
        board.bombsRemaining = bombNumber;
        return board;
    }
};

fn neighbor_pos(allocator: Allocator, x: usize, y: usize) ![]@Vector(2, usize) {
    const xi = @intCast(i32, x);
    const yi = @intCast(i32, y);
    const vectors = [_]@Vector(2, i32){
        .{ xi - 1, yi }, 
        .{ xi + 1, yi }, 
        .{ xi, yi - 1 }, 
        .{ xi, yi + 1 }, 
        .{ xi - 1, yi - 1 }, 
        .{ xi - 1, yi + 1 }, 
        .{ xi + 1, yi - 1 }, 
        .{ xi + 1, yi + 1 } 
    };
    var counter: usize = 0;
    var result: []Position = try allocator.alloc(Position, 8);
    for (vectors) |vec| {
        if (vec[0] < 0 or vec[0] >= BOARD_W or vec[1] < 0 or vec[1] >= BOARD_H) {
            continue;
        }
        std.debug.assert(@intCast(usize, vec[0]) == vec[0]);
        std.debug.assert(@intCast(usize, vec[1]) == vec[1]);
        result[counter] = .{
            @intCast(usize, vec[0]), 
            @intCast(usize, vec[1])
        };
        counter += 1;
    }
    return result[0..counter];
}

const GameCtx = struct {
    tileTextures: [10]*c.SDL_Texture,
    flagTexture: *c.SDL_Texture,
    bombTexture: *c.SDL_Texture,
    board: Board,
    renderer: *c.SDL_Renderer,
    window: *c.SDL_Window,
    allocator: Allocator,
    const Self = @This();
    pub fn init(allocator: Allocator) !Self {
        var ctx: Self = undefined;
        ctx.allocator = allocator;
        if (c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS) < 0) return error.SDLInitFailed;
        const window = c.SDL_CreateWindow("uwu", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, SCREEN_W, SCREEN_H, 0).?;
        const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_ACCELERATED | c.SDL_RENDERER_PRESENTVSYNC).?;

        ctx.window = window;
        ctx.renderer = renderer;
        var tileTextures: [10]*c.SDL_Texture = undefined;
        inline for (tileTextures, 0..) |_, i| {
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

        return ctx;
    }
    pub fn genBoard(self: *Self, firstClickPos: Position) !void {
        self.board = try Board.init(self.allocator, BOMB_NUMBER, firstClickPos);
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
        for (self.board.tiles, 0..) |ts, y| {
            for (ts, 0..) |t, x| {
                const img = switch (t.revealed) {
                    true => switch (t.isBomb) {
                        true => self.bombTexture,
                        false => self.tileTextures[t.value],
                    },
                    false => switch (t.flagged) {
                        true => self.flagTexture,
                        false => continue,
                    },
                };
                const rect = c.SDL_Rect{ 
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

    pub fn reveal(self: *Self, pos: @Vector(2, usize)) bool {
        var wasBomb = false;
        const tile = &self.board.tiles[pos[0]][pos[1]];
        if (tile.isBomb) wasBomb = true;
        if (tile.revealed) return false;
        if (tile.flagged) return false;
        tile.revealed = true;
        if (tile.value == 0) {
            const neighbors = tile.near;
            for (neighbors) |npos| {
                const neighbor = &self.board.tiles[npos[0]][npos[1]];
                if (neighbor.revealed or neighbor.flagged) continue;
                if (self.reveal(npos)) wasBomb = true;
            }
        }
        return wasBomb;
    }
    pub fn left_click(self: *Self, pos: @Vector(2, usize)) bool {
        const tile = &self.board.tiles[pos[0]][pos[1]];
        switch (tile.revealed) {
            false => {
                return self.reveal(pos);
            },
            true => {
                var flag_counter: usize = 0;
                for (tile.near) |npos| {
                    const neighbor = &self.board.tiles[npos[0]][npos[1]];
                    if (neighbor.flagged) flag_counter += 1;
                }
                if (flag_counter >= tile.value) {
                    var wasBomb = false;
                    for (tile.near) |npos| {
                        const neighbor = &self.board.tiles[npos[0]][npos[1]];
                        if (!neighbor.revealed and !neighbor.flagged) {
                             if (self.reveal(npos)) wasBomb = true;
                        }
                    }
                    return wasBomb;
                }
            }
        }
        return false;
    }
    pub fn right_click(self: *Self, pos: @Vector(2, usize)) void {
        const tile = &self.board.tiles[pos[0]][pos[1]];
        switch (tile.revealed) {
            false => tile.flagged = !tile.flagged,
            true => {
                var counter: usize = 0;
                for (tile.near) |npos| {
                    const neighbor = &self.board.tiles[npos[0]][npos[1]];
                    if (neighbor.flagged or !neighbor.revealed) counter += 1;
                }
                if (counter == tile.value) {
                    for (tile.near) |npos| {
                        const neighbor = &self.board.tiles[npos[0]][npos[1]];
                        if (!neighbor.flagged and !neighbor.revealed) {
                            neighbor.flagged = true;
                        }
                    }
                }
             },
        }
    }
};

fn coord_to_pos(x: u32, y: u32) @Vector(2, usize) {
    const ny = y / @intCast(u32, TILE_H);
    const nx = x / @intCast(u32, TILE_W);
    return .{
        std.math.min(ny, @intCast(u32, BOARD_H)),
        std.math.min(nx, @intCast(u32, BOARD_W))
    };
}

const GameOverState = union(enum) {
    loss: Position,
    win,
    none
};

pub fn main() !void {
    var quit = false;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var firstClick = true;
    var firstClickPos: Position = undefined;


    var ctx = try GameCtx.init(allocator);
    defer ctx.deinit();
    while (firstClick and !quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            if (event.type == c.SDL_MOUSEBUTTONDOWN and event.button.button == c.SDL_BUTTON_LEFT) {
                const x = @intCast(u32, event.button.x);
                const y = @intCast(u32, event.button.y);
                firstClickPos = coord_to_pos(x, y);
                firstClick = false;
            } else if (event.type == c.SDL_QUIT) quit = true;
        }
        _ = c.SDL_SetRenderDrawColor(ctx.renderer, 0xFF, 0xFF, 0xFF, 0xFF);
        _ = c.SDL_RenderClear(ctx.renderer);
        _ = c.SDL_RenderPresent(ctx.renderer);
    }
    try ctx.genBoard(firstClickPos);
    _ = ctx.reveal(firstClickPos);

    while (true) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            if (quit) {
                if (event.type == c.SDL_KEYDOWN) {
                    if (event.key.keysym.sym == 'q') return;
                }
            } else {
                switch (event.type) {
                    c.SDL_QUIT => quit = true,
                    c.SDL_MOUSEBUTTONDOWN => {
                        switch (event.button.button) {
                            c.SDL_BUTTON_LEFT => {
                                const x = @intCast(u32, event.button.x);
                                const y = @intCast(u32, event.button.y);
                                const pos = coord_to_pos(x, y);
                                if (ctx.left_click(pos)) {
                                    quit = true;
                                }
                            },
                            c.SDL_BUTTON_RIGHT => {
                                const x = @intCast(u32, event.button.x);
                                const y = @intCast(u32, event.button.y);
                                const pos = coord_to_pos(x, y);
                                ctx.right_click(pos);
                            },
                            else => {},
                        }
                    },
                    else => {},
                }
            }
        }
        ctx.render();
    }
}
