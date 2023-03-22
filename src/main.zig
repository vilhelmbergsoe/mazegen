const std = @import("std");
const rand = std.rand;
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

var window_width: c_int = 800;
var window_height: c_int = 800;
const cell_wall_width: f32 = 1.0;

const N = 1;
const S = 2;
const E = 4;
const W = 8;

const DX = blk: {
    var res = std.mem.zeroes([9]i8);
    res[N] = 0;
    res[E] = 1;
    res[S] = 0;
    res[W] = -1;
    break :blk res;
};
const DY = blk: {
    var res = std.mem.zeroes([9]i8);
    res[N] = -1;
    res[E] = 0;
    res[S] = 1;
    res[W] = 0;
    break :blk res;
};
const OPPOSITE = blk: {
    var res = std.mem.zeroes([9]u8);
    res[N] = S;
    res[E] = W;
    res[S] = N;
    res[W] = E;
    break :blk res;
};

fn usage(program: []u8, errormessage: []const u8) !void {
    try std.io.getStdErr().writer().print(
        \\Generate awesome mazes with the recursive backtracking algorithm
        \\
        \\Usage:
        \\  {s} <width> <height> <seed*>
        \\
        \\Options:
        \\
        \\  width:             usize integer
        \\  height:            usize integer
        \\  seed (*optional):  unsigned 64-bit integer  (default = random)
        \\
        \\Error:
        \\ {s}
        \\
    , .{ program, errormessage });
    std.os.exit(1);
}

fn carve_path(maze: *Maze, random: rand.Random, cx: usize, cy: usize) void {
    var directions = [4]u8{ N, S, E, W };
    random.shuffle(u8, directions[0..]);

    for (directions) |direction| {
        const dx: i8 = DX[direction];
        const dy: i8 = DY[direction];

        // This is kind of awkward but i think i need it in order to check if we're out of bounds
        const nx: isize = @intCast(isize, cx) + dx;
        const ny: isize = @intCast(isize, cy) + dy;

        if (((nx < maze.width) and (nx >= 0)) and ((ny < maze.height) and (ny >= 0))) {
            if (maze.get(@intCast(usize, nx), @intCast(usize, ny)) == 0) {
                maze.set(cx, cy, direction);
                maze.set(@intCast(usize, nx), @intCast(usize, ny), OPPOSITE[direction]);
                carve_path(maze, random, @intCast(usize, nx), @intCast(usize, ny));
            }
        }
    }
}

const Maze = struct {
    width: usize,
    height: usize,
    cell_width: f32,
    cell_height: f32,
    grid: []u8,
    fn set(self: Maze, x: usize, y: usize, value: u8) void {
        self.grid[y * self.width + x] |= value;
    }
    fn get(self: Maze, x: usize, y: usize) u8 {
        return self.grid[y * self.width + x];
    }
};

pub fn main() !void {
    // Set up allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    // Parse and sanitize command line arguments
    const args = std.os.argv;
    const program = std.mem.span(args[0]);

    var maze_width: usize = undefined;
    var maze_height: usize = undefined;
    var seed: ?u64 = null;
    switch (args.len) {
        3, 4 => {
            maze_width = try std.fmt.parseUnsigned(usize, std.mem.span(args[1]), 10);
            maze_height = try std.fmt.parseUnsigned(usize, std.mem.span(args[2]), 10);
            if (args.len == 4)
                seed = try std.fmt.parseUnsigned(u64, std.mem.span(args[3]), 10);
        },
        else => {
            try usage(program, "Missing arguments");
            return;
        },
    }

    const cell_width: f32 = @intToFloat(f32, window_width) / @intToFloat(f32, maze_width);
    const cell_height: f32 = @intToFloat(f32, window_height) / @intToFloat(f32, maze_height);

    // Make prng with seed if provided, otherwise a random one will be generated
    var prng = rand.DefaultPrng.init(seed orelse blk: {
        var rseed: u64 = undefined;
        try std.os.getrandom(std.mem.asBytes(&rseed));
        std.debug.print("seed: {}\n", .{rseed});
        break :blk rseed;
    });
    const random = prng.random();

    // Create maze struct
    var maze = Maze{
        .width = maze_width,
        .height = maze_height,
        .cell_width = cell_width,
        .cell_height = cell_height,

        // Allocate memory for grid as onedimensional array
        .grid = blk: {
            var res = try allocator.alloc(u8, maze_width * maze_height);
            for (res, 0..) |_, i| {
                res[i] = 0;
            }
            break :blk res;
        },
    };

    // Initialize SDL
    if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
        c.SDL_Log("Unable to initialize SDL: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    }
    defer c.SDL_Quit();

    // Create SDL window
    const window = c.SDL_CreateWindow("mazegen", c.SDL_WINDOWPOS_UNDEFINED, c.SDL_WINDOWPOS_UNDEFINED, window_width, window_height, c.SDL_WINDOW_OPENGL) orelse
        {
        c.SDL_Log("Unable to create window: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyWindow(window);

    // Create SDL renderer
    const renderer = c.SDL_CreateRenderer(window, -1, c.SDL_RENDERER_PRESENTVSYNC) orelse {
        c.SDL_Log("Unable to create renderer: %s", c.SDL_GetError());
        return error.SDLInitializationFailed;
    };
    defer c.SDL_DestroyRenderer(renderer);

    // Make window resizable
    _ = c.SDL_SetWindowResizable(window, c.SDL_TRUE);

    carve_path(&maze, random, 0, 0);

    var quit = false;
    while (!quit) {
        var event: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&event) != 0) {
            switch (event.type) {
                c.SDL_QUIT => {
                    quit = true;
                },
                c.SDL_KEYDOWN => {
                    if (@intCast(c_int, event.key.keysym.sym) == c.SDLK_q) quit = true;
                },
                else => {},
            }
        }

        // Get window size for if it has been resized and recalculate the cell_width and cell_height
        _ = c.SDL_GetWindowSize(window, &window_width, &window_height);
        maze.cell_width = @intToFloat(f32, window_width) / @intToFloat(f32, maze_width);
        maze.cell_height = @intToFloat(f32, window_height) / @intToFloat(f32, maze_height);

        _ = c.SDL_SetRenderDrawColor(renderer, 0x18, 0x18, 0x18, 0xff);
        _ = c.SDL_RenderClear(renderer);

        var y: usize = 0;
        while (y < maze_height) {
            var x: usize = 0;
            while (x < maze_width) {
                var rect: c.SDL_FRect = undefined;
                const cell = maze.get(x, y);

                _ = c.SDL_SetRenderDrawColor(renderer, 0xee, 0xee, 0xee, 0xff);

                rect.x = @intToFloat(f32, x) * maze.cell_width + cell_wall_width;
                rect.y = @intToFloat(f32, y) * maze.cell_height + cell_wall_width;

                if (cell & E != 0) {
                    rect.w = maze.cell_width * 2 - cell_wall_width * 2;
                    rect.h = maze.cell_height - cell_wall_width * 2;
                    _ = c.SDL_RenderFillRectF(renderer, &rect);
                }
                if (cell & S != 0) {
                    rect.w = maze.cell_width - cell_wall_width * 2;
                    rect.h = maze.cell_height * 2 - cell_wall_width * 2;
                    _ = c.SDL_RenderFillRectF(renderer, &rect);
                }

                x += 1;
            }
            y += 1;
        }
        _ = c.SDL_RenderPresent(renderer);
    }
}
