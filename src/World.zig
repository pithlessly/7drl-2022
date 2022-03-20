const std = @import("std");
const Allocator = std.mem.Allocator;
const Rng = std.rand.DefaultPrng;

const Vec2 = @import("geometry.zig").Vec2;

pub const TileKind = enum { empty, solid };
pub const Tile = struct {
    kind: TileKind,
    is_visible: bool,
};

const Player = struct {
    loc: Vec2,
    omniscient: bool,
};

const Map = struct {
    width: u16,
    height: u16,
    tiles: []Tile,

    fn init(alloc: Allocator, rand: std.rand.Random, width: u16, height: u16) !Map {
        const tiles = try alloc.alloc(Tile, @as(usize, width) * @as(usize, height));
        for (tiles) |*t| t.* = .{
            .is_visible = false,
            .kind = if (rand.uintLessThan(u32, 5) == 0)
                TileKind.empty
            else
                TileKind.solid,
        };
        return Map{ .width = width, .height = height, .tiles = tiles };
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
        return (self.tile(at) orelse return false).kind == .solid;
    }
};

rng: Rng,
player: Player,
map: Map,

const World = @This();

pub fn init(alloc: Allocator, width: u16, height: u16) !World {
    var rng = Rng.init(std.crypto.random.int(u64));
    const map = try Map.init(alloc, rng.random(), width, height);
    return World{
        .rng = rng,
        .player = .{ .loc = Vec2.new(5, 5), .omniscient = true },
        .map = map,
    };
}

pub fn playerLoc(self: World) Vec2 {
    return self.player.loc;
}

pub fn mapTile(self: World, at: Vec2) ?*Tile {
    return self.map.tile(at);
}

pub fn movePlayer(self: *World, dx: i2, dy: i2) void {
    const new_loc = Vec2.new(dx, dy).add(self.player.loc);
    if (!self.map.isSolid(new_loc))
        self.player.loc = new_loc;
}

pub fn toggleOmniscience(self: *World) void {
    self.player.omniscient = !self.player.omniscient;
}

pub fn recomputeVisibility(self: *World) void {
    const omniscient = self.player.omniscient;
    self.map.resetVisibility(omniscient);
    if (!omniscient) {
        std.debug.panic("todo: compute vision", .{});
    }
}

test "compilation" {
    std.testing.refAllDecls(Player);
    std.testing.refAllDecls(Map);
    std.testing.refAllDecls(World);
}
