const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const termios = @cImport(@cInclude("termios.h"));

const Vec2 = @import("geometry.zig").Vec2;
const World = @import("World.zig");

var old_settings_global: termios.struct_termios = undefined;
var in_raw_mode_global: bool = false;

fn enterRawMode() !void {
    assert(!in_raw_mode_global);
    var settings: termios.struct_termios = undefined;
    if (termios.tcgetattr(std.os.STDOUT_FILENO, &settings) < 0)
        return error.RawMode;
    old_settings_global = settings;
    termios.cfmakeraw(&settings);
    if (termios.tcsetattr(std.os.STDOUT_FILENO, termios.TCSANOW, &settings) < 0)
        return error.RawMode;
    in_raw_mode_global = true;
}

fn exitRawMode() void {
    assert(in_raw_mode_global);
    _ = termios.tcsetattr(std.os.STDOUT_FILENO, termios.TCSANOW, &old_settings_global);
    in_raw_mode_global = false;
}

const Reader = std.fs.File.Reader;
const FileWriter = std.fs.File.Writer;
const WriterBuffer = std.io.BufferedWriter(4096, FileWriter);
const Writer = WriterBuffer.Writer;

fn beginUI(w: FileWriter) !void {
    try enterRawMode();
    errdefer exitRawMode();
    try w.print("\x1b[?1049h", .{}); // switch to alternate screen
}

fn endUI(w: FileWriter) void {
    w.print("\x1b[?1049l", .{}) catch {}; // switch to main screen
    exitRawMode(); // make sure to do this even if the write fails
}

fn moveCursorAbsolute(w: Writer, x: u16, y: u16) !void {
    try w.print("\x1b[{};{}H", .{ y + 1, x + 1 }); // CHA
}

fn moveCursor(w: Writer, old_x: u16, old_y: u16, new_x: u16, new_y: u16) !void {
    var dy = @as(i32, new_y) - @as(i32, old_y);
    var dx = @as(i32, new_x) - @as(i32, old_x);
    return if (dy < 0)
        moveCursorAbsolute(w, new_x, new_y)
    else if (dy == 0)
        if (dx < 0)
            w.print("\x1b[{}D", .{-dx}) // CUB
        else if (dx > 0)
            w.print("\x1b[{}C", .{dx}) // CUF
        else {}
    else if (dx == 0 and dy > 0)
        if (dy == 1)
            w.print("\n", .{})
        else
            w.print("\x1b[{}B", .{dy}) // CUD
    else if (new_x == 0 and dy > 0)
        if (dy == 1)
            w.print("\r\n", .{})
        else
            w.print("\x1b[{}E", .{dy}) // CNL
    else
        moveCursorAbsolute(w, new_x, new_y);
}

const Screen = struct {
    const Color = enum { default };

    const Cell = struct {
        c: u16,
        fg: Color,

        fn eq(self: Cell, other: Cell) bool {
            return std.meta.eql(self, other);
        }

        fn charOfTile(t: World.Tile) u16 {
            return switch (t.kind) {
                .empty => '.',
                .solid => '#',
            };
        }

        fn compute(world: World, at: Vec2) Cell {
            return .{
                .c = if (world.hasPlayerAt(at))
                    '@'
                else blk: {
                    const t = world.mapTile(at).?.*;
                    break :blk if (t.is_visible)
                        charOfTile(t)
                    else
                        ' ';
                },
                .fg = .default,
            };
        }
    };

    width: u16,
    height: u16,
    cells: []Cell,
    cursor_x: u16,
    cursor_y: u16,
    wb: WriterBuffer,

    fn init(alloc: Allocator, wb: WriterBuffer, width: u16, height: u16) !Screen {
        assert(width > 0 and height > 0);
        try wb.unbuffered_writer.print("\x1b[H\x1b[J", .{}); // clear screen & move to top
        const n_cells = @as(usize, width) * @as(usize, height);
        const cells = try alloc.alloc(Cell, n_cells);
        std.mem.set(Cell, cells, .{ .c = ' ', .fg = .default });
        return Screen{
            .width = width,
            .height = height,
            .cells = cells,
            .cursor_x = 0,
            .cursor_y = 0,
            .wb = wb,
        };
    }

    fn deinit(self: Screen, alloc: Allocator) void {
        alloc.free(self.cells);
    }

    fn update(self: *Screen, world: World) !void {
        const writer = self.wb.writer();
        var cx = self.cursor_x;
        var cy = self.cursor_y;
        var cell_idx: usize = 0;
        var y: u16 = 0;
        while (y < self.height) : (y += 1) {
            var x: u16 = 0;
            while (x < self.width) : (x += 1) {
                const at = Vec2.new(@intCast(i16, x), @intCast(i16, y));
                const cur_cell = Cell.compute(world, at);
                const old_cell = &self.cells[cell_idx];
                cell_idx += 1;
                if (!old_cell.eq(cur_cell)) {
                    try moveCursor(writer, cx, cy, x, y);
                    try writer.print("{u}", .{cur_cell.c});
                    cx = x + 1;
                    cy = y;
                    old_cell.* = cur_cell;
                }
            }
        }
        self.cursor_x = cx;
        self.cursor_y = cy;
        try self.wb.flush();
    }
};

const Key = enum { ctrl_c, y, u, h, j, k, l, v, b, n, question_mark, other };

fn readKey(r: Reader) !Key {
    return switch (try r.readByte()) {
        '\x03' => Key.ctrl_c,
        'y' => Key.y,
        'u' => Key.u,
        'h' => Key.h,
        'j' => Key.j,
        'k' => Key.k,
        'l' => Key.l,
        'v' => Key.v,
        'b' => Key.b,
        'n' => Key.n,
        '?' => Key.question_mark,
        else => Key.other,
    };
}

fn runGame(alloc: Allocator, r: Reader, wb: WriterBuffer) !void {
    const width = 80;
    const height = 24;
    var world = try World.init(alloc, width, height);
    defer world.deinit();
    var screen = try Screen.init(alloc, wb, width, height);
    defer screen.deinit(alloc);
    while (true) {
        try world.recomputeVisibility();
        try screen.update(world);
        const k = try readKey(r);
        std.debug.print("got key: {}\n", .{k});
        switch (k) {
            .ctrl_c => break,
            .h => try world.movePlayer(-1,  0),
            .j => try world.movePlayer( 0,  1),
            .k => try world.movePlayer( 0, -1),
            .l => try world.movePlayer( 1,  0),
            .v => try world.toggleOmniscience(),
            .question_mark => try world.addPlayer(),
            else => {}
        }
    }
}

pub fn main() anyerror!void {
    const stdout = std.io.getStdOut().writer();
    const stdin = std.io.getStdIn().reader();
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = alloc.deinit();
    try beginUI(stdout);
    defer endUI(stdout);
    var stdout_buf = std.io.bufferedWriter(stdout);
    try runGame(alloc.allocator(), stdin, stdout_buf);
    try stdout_buf.flush();
}

test "compilation" {
    std.testing.refAllDecls(@This());
    std.testing.refAllDecls(Screen);
}
