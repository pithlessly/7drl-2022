const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Rng = std.rand.DefaultPrng;

fn choose(xs: anytype, rand: std.rand.Random) @TypeOf(&xs[0]) {
    assert(xs.len > 0);
    return &xs[rand.uintLessThan(usize, xs.len)];
}

const Vec2 = @import("geometry.zig").Vec2;
const Visibility = @import("vision.zig").Visibility;

pub const TileKind = enum { empty, solid };
pub const Tile = struct {
    kind: TileKind,
    is_visible: bool,
};

const Player = struct {
    // invariant: this should be non-empty and contain no duplicates
    const Locs = std.ArrayList(Vec2);
    locs: Locs,
    omniscient: bool,

    fn deinit(self: Player) void {
        self.locs.deinit();
    }
};

const Map = struct {
    width: u15,
    height: u15,
    tiles: []Tile,

    fn init(alloc: Allocator, rand: std.rand.Random, width: u15, height: u15) !Map {
        const tiles = try alloc.alloc(Tile, @as(usize, width) * @as(usize, height));
        for (tiles) |*t| t.* = .{
            .is_visible = false,
            .kind = if (rand.uintLessThan(u32, 5) == 0)
                TileKind.empty
            else
                TileKind.solid,
        };
        var self = Map{ .width = width, .height = height, .tiles = tiles };
        self.placeRooms(rand);
        return self;
    }

    fn placeRooms(self: *Map, rand: std.rand.Random) void {
        assert(self.width == 80 and self.height == 24); // will have to be changed if this changes
        var group: i16 = 0;
        while (group < 16) : (group += 1) {
            // compute the widths of boundaries between rooms
            var boundaries = [1]u8{1} ** 6;
            {
                var i: u32 = 0;
                while (i < 3) : (i += 1)
                    choose(&boundaries, rand).* += 1;
            }
            // place rooms on the map
            var room: usize = 0;
            var y: i16 = 0;
            const base_x = group * 5 + 1;
            while (room < 5) : (room += 1) {
                y += boundaries[room];
                if (rand.uintLessThan(usize, 7) == 0) {
                    y += 3;
                    continue;
                }
                comptime var i = 0;
                inline while (i < 3) : (i += 1) {
                    comptime var j = 0;
                    inline while (j < 3) : (j += 1)
                        self.tile(Vec2.new(base_x + j, y)).?.kind = TileKind.empty;
                    y += 1;
                }
            }
        }
    }

    fn deinit(self: Map, alloc: Allocator) void {
        alloc.free(self.tiles);
    }

    fn resetVisibility(self: *Map, status: bool) void {
        for (self.tiles) |*t| t.is_visible = status;
    }

    fn tile(self: Map, at: Vec2) ?*Tile {
        if (0 <= at.x and at.x < self.width and 0 <= at.y and at.y < self.height) {
            const idx = @intCast(usize, at.y) * self.width + @intCast(usize, at.x);
            return &self.tiles[idx];
        } else {
            return null;
        }
    }

    fn isSolid(self: Map, at: Vec2) bool {
        return (self.tile(at) orelse return true).kind == .solid;
    }
};

rng: Rng,
player: Player,
map: Map,

const World = @This();

pub fn init(alloc: Allocator, width: u15, height: u15) !World {
    var rng = Rng.init(std.crypto.random.int(u64));
    const map = try Map.init(alloc, rng.random(), width, height);
    errdefer map.deinit(alloc);
    var locs = try Player.Locs.initCapacity(alloc, 20);
    locs.appendAssumeCapacity(Vec2.new(22, 3));
    return World{
        .rng = rng,
        .player = .{ .locs = locs, .omniscient = true },
        .map = map,
    };
}

pub fn deinit(self: World, alloc: Allocator) void {
    self.map.deinit(alloc);
    self.player.deinit();
}

pub fn hasPlayerAt(self: World, at: Vec2) bool {
    for (self.player.locs.items) |loc|
        if (loc.eq(at))
            return true;
    return false;
}

pub fn mapTile(self: World, at: Vec2) ?*Tile {
    return self.map.tile(at);
}

pub fn movePlayer(self: *World, dx: i2, dy: i2) void {
    const old_loc = choose(self.player.locs.items, self.rng.random()).*;
    const new_loc = Vec2.new(dx, dy).add(old_loc);
    if (self.map.isSolid(new_loc)) {
        return;
    }
    self.player.locs.clearRetainingCapacity();
    self.player.locs.appendAssumeCapacity(new_loc);
}

pub fn toggleOmniscience(self: *World) void {
    self.player.omniscient = !self.player.omniscient;
}

pub fn recomputeVisibility(self: *World) void {
    const omniscient = self.player.omniscient;
    self.map.resetVisibility(omniscient);
    if (!omniscient)
        for (self.player.locs.items) |player_loc|
            (Visibility(struct {
                map: *Map,
                const Self = @This();
                pub fn isOpaque(self_: Self, at: Vec2) bool {
                    return self_.map.isSolid(at);
                }
                pub fn magnitude(at: Vec2) u32 {
                    return Vec2.new(0, 0).dist(at);
                }
                pub fn markVisible(self_: Self, at: Vec2) void {
                    if (self_.map.tile(at)) |tile|
                        tile.is_visible = true;
                }
            }){
                .world = .{ .map = &self.map },
                .origin = player_loc,
                .max_distance = 50,
            }).compute();
}

pub fn addPlayer(self: *World) !void {
    const x = self.rng.random().uintLessThan(u15, self.map.width);
    const y = self.rng.random().uintLessThan(u15, self.map.height);
    const loc = Vec2.new(x, y);
    if (self.hasPlayerAt(loc))
        std.debug.print("location ({},{}) is already taken\n", .{x, y})
    else
        try self.player.locs.append(loc);
}

test "compilation" {
    std.testing.refAllDecls(Player);
    std.testing.refAllDecls(Map);
    std.testing.refAllDecls(World);
}
