const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Rng = std.rand.DefaultPrng;

fn choose(xs: anytype, rand: std.rand.Random) @TypeOf(&xs[0]) {
    assert(xs.len > 0);
    return &xs[rand.uintLessThan(usize, xs.len)];
}

const WorldHash = struct {
    state: u64 = 0x34bbf6d13d813f47,
    const mul = 0xc6a4a7935bd1e995;

    fn update(self: *WorldHash, val: u64) void {
        var k = val *% mul;
        k ^= (k >> 47);
        self.state = ((k *% mul) ^ self.state) *% mul;
    }

    fn finalize(self: WorldHash) u64 {
        var hash = self.state;
        hash ^= (hash >> 47);
        hash *%= mul;
        hash ^= (hash >> 47);
        return hash;
    }
};

const Vec2 = @import("geometry.zig").Vec2;
const Visibility = @import("vision.zig").Visibility;

pub const TileKind = enum { empty, solid };
pub const Tile = struct {
    kind: TileKind,
    is_visible: bool,
    is_visited: bool,
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

    // all positions we should consider for player positions next time we call `recomputeVisibility`.
    // it's fine for this list to contain duplicates.
    next_visible_candidates: PosBuf,
    // conceptually this state is only used in `recomputeVisibility`,
    // but we reuse the allocation
    marked_visible_buf: PosBuf,
    const PosBuf = std.ArrayListUnmanaged(Vec2);

    fn init(alloc: Allocator, rand: std.rand.Random, width: u15, height: u15) !Map {
        const tiles = try alloc.alloc(Tile, @as(usize, width) * @as(usize, height));
        for (tiles) |*t| t.* = .{
            .is_visible = false,
            .is_visited = false,
            .kind = if (rand.uintLessThan(u32, 5) == 0)
                TileKind.empty
            else
                TileKind.solid,
        };
        var self = Map{
            .width = width,
            .height = height,
            .tiles = tiles,
            .next_visible_candidates = PosBuf{},
            .marked_visible_buf = PosBuf{},
        };
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

    fn deinit(self: *Map, alloc: Allocator) void {
        alloc.free(self.tiles);
        self.next_visible_candidates.deinit(alloc);
        self.marked_visible_buf.deinit(alloc);
    }

    fn resetVisibility(self: *Map, status: bool) void {
        for (self.tiles) |*t| t.is_visible = status;
    }

    // collect all the tiles visible from `at` into `marked_visible_buf` in sorted order.
    // return the number of tiles.
    fn computeVisibility(self: *Map, alloc: Allocator, origin: Vec2) ?usize {
        self.marked_visible_buf.clearRetainingCapacity();
        (Visibility(struct {
            alloc: Allocator,
            map: *Map,
            const Self = @This();
            pub fn isOpaque(self_: Self, at: Vec2) bool {
                return self_.map.isSolid(at);
            }
            pub fn magnitude(at: Vec2) u32 {
                return Vec2.new(0, 0).dist(at);
            }
            pub fn markVisible(self_: Self, at: Vec2) !void {
                if (self_.map.tile(at)) |t| {
                    if (t.is_visible)
                        return error.Bailout;
                    self_.map.marked_visible_buf.append(self_.alloc, at) catch {};
                }
            }
        }, error{Bailout}){
            .world = .{ .alloc = alloc, .map = self },
            .origin = origin,
            .max_distance = 50,
        }).compute() catch |e| switch (e) {
            error.Bailout => {
                self.marked_visible_buf.clearRetainingCapacity();
                return null;
            },
        };
        assert(self.marked_visible_buf.items.len > 0);
        // sort visible tiles (specific order is irrelevant, just needs to be consistent)
        std.sort.sort(Vec2, self.marked_visible_buf.items, {}, struct {
            fn lt(_: void, lhs: Vec2, rhs: Vec2) bool {
                return lhs.serialize() < rhs.serialize();
            }
        }.lt);
        // deduplicate
        if (self.marked_visible_buf.items.len > 1) {
            const visible_tiles = self.marked_visible_buf.items;
            var read_idx: usize = 1;
            var write_idx: usize = 1;
            while (read_idx < visible_tiles.len) : (read_idx += 1) {
                const lhs = visible_tiles[read_idx - 1];
                const rhs = visible_tiles[read_idx];
                if (!lhs.eq(rhs)) {
                    visible_tiles[write_idx] = rhs;
                    write_idx += 1;
                }
            }
            self.marked_visible_buf.shrinkRetainingCapacity(write_idx);
        }
        return self.marked_visible_buf.items.len;
    }

    fn hashVisibleBuf(self: Map, at: Vec2) u64 {
        var hasher = WorldHash{};
        for (self.marked_visible_buf.items) |pos| {
            const til = self.tile(pos).?;
            hasher.update(pos.serialize() -% at.serialize());
            hasher.update(@enumToInt(til.kind));
        }
        return hasher.finalize();
    }

    fn contains(self: Map, at: Vec2) bool {
        return 0 <= at.x and at.x < self.width and 0 <= at.y and at.y < self.height;
    }

    fn tileIdx(width: u16, at: Vec2) usize {
        return @intCast(usize, at.y) * width + @intCast(usize, at.x);
    }

    fn tile(self: Map, at: Vec2) ?*Tile {
        if (self.contains(at)) {
            return &self.tiles[tileIdx(self.width, at)];
        } else {
            return null;
        }
    }

    fn isSolid(self: Map, at: Vec2) bool {
        return (self.tile(at) orelse return true).kind == .solid;
    }

    fn surroundings(self: Map, at: Vec2) u64 {
        var result: [8]u8 = undefined;
        comptime var i = 0;
        inline for ([3]i2{ -1, 0, 1 }) |dy| {
            inline for ([3]i2{ -1, 0, 1 }) |dx| {
                if (dx != 0 or dy != 0) {
                    const pos = Vec2.new(dx, dy).add(at);
                    result[i] = if (self.tile(pos)) |t|
                        1 + @as(u8, @enumToInt(t.kind))
                    else
                        0;
                    i += 1;
                }
            }
        }
        return @bitCast(u64, result);
    }
};

rng: Rng,
alloc: Allocator,
player: Player,
map: Map,

const World = @This();

pub fn init(alloc: Allocator, width: u15, height: u15) !World {
    var rng = Rng.init(std.crypto.random.int(u64));
    var map = try Map.init(alloc, rng.random(), width, height);
    errdefer map.deinit(alloc);
    var locs = try Player.Locs.initCapacity(alloc, 20);
    locs.appendAssumeCapacity(Vec2.new(22, 3));
    return World{
        .rng = rng,
        .alloc = alloc,
        .player = .{ .locs = locs, .omniscient = true },
        .map = map,
    };
}

pub fn deinit(self: *World) void {
    self.map.deinit(self.alloc);
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

// randomly select one of the player's locations as the canonical one, and move the rest to candidates
pub fn focusPlayer(self: *World) !void {
    const locs = &self.player.locs;
    self.rng.random().shuffle(Vec2, locs.items);

    // at this point, the first location is the canonical one, and we will soon truncate the rest
    const canonical_surroundings = self.map.surroundings(locs.items[0]);
    self.map.next_visible_candidates.clearRetainingCapacity();
    for (locs.items[1..]) |loc|
        if (canonical_surroundings == self.map.surroundings(loc))
            try self.map.next_visible_candidates.append(self.alloc, loc);
    locs.shrinkRetainingCapacity(1);

    // add all map positions which match the surroundings as candidates
    {
        const candidates = &self.map.next_visible_candidates;
        const additional_candidates_start_idx = candidates.items.len;
        var y: i16 = 0;
        while (y < self.map.height) : (y += 1) {
            var x: i16 = 0;
            while (x < self.map.width) : (x += 1) {
                const loc = Vec2.new(x, y);
                if (!self.map.isSolid(loc) and
                    canonical_surroundings == self.map.surroundings(loc))
                    try candidates.append(self.alloc, loc);
            }
        }
        // these new candidates should be visited in random order
        self.rng.random().shuffle(Vec2, candidates.items[additional_candidates_start_idx..]);
    }
}

pub fn movePlayer(self: *World, dx: i2, dy: i2) !void {
    // move all players that can be moved
    const locs = &self.player.locs;
    {
        var read_idx: usize = 0;
        var write_idx: usize = 0;
        while (read_idx < locs.items.len) : (read_idx += 1) {
            const old_loc = locs.items[read_idx];
            const new_loc = old_loc.add(Vec2.new(dx, dy));
            if (!self.map.isSolid(new_loc)) {
                locs.items[write_idx] = new_loc;
                write_idx += 1;
            }
        }
        // can't move in that direction
        if (write_idx == 0)
            return; // no changes were made
        locs.shrinkRetainingCapacity(write_idx);
    }
    try self.focusPlayer();
    try self.recomputeVisibility();
}

pub fn toggleOmniscience(self: *World) !void {
    self.player.omniscient = !self.player.omniscient;
    try self.focusPlayer();
    try self.recomputeVisibility();
}

pub fn recomputeVisibility(self: *World) !void {
    self.map.resetVisibility(self.player.omniscient);
    if (self.player.omniscient)
        return;

    const timer = std.time.Timer.start() catch unreachable;
    defer std.debug.print("computed visibility in {}µs\n", .{timer.read() / 1000});

    const map = &self.map;
    const player_locs = &self.player.locs;
    assert(player_locs.items.len == 1);
    const canonical_player_loc = player_locs.items[0];
    const canonical_vis_length = map.computeVisibility(self.alloc, canonical_player_loc) orelse
        // this indicates the vision computation aborted because a tile already marked as
        // visible was reached, but this is impossible because we just cleared everything
        unreachable;
    const canonical_vis_hash = map.hashVisibleBuf(canonical_player_loc);

    for (map.marked_visible_buf.items) |pos| {
        const tile = map.tile(pos).?;
        tile.is_visible = true;
        tile.is_visited = true;
    }

    for (map.next_visible_candidates.items) |loc|
        if (map.computeVisibility(self.alloc, loc)) |vis_length|
            if (canonical_vis_length == vis_length and
                canonical_vis_hash == map.hashVisibleBuf(loc))
            {
                try player_locs.append(loc);
                for (map.marked_visible_buf.items) |pos| {
                    const tile = map.tile(pos).?;
                    assert(!tile.is_visible);
                    tile.is_visible = true;
                    tile.is_visited = true;
                }
            };
}

pub fn jumpPlayer(self: *World) !void {
    self.player.locs.clearRetainingCapacity();
    while (true) {
        const x = self.rng.random().uintLessThan(u15, self.map.width);
        const y = self.rng.random().uintLessThan(u15, self.map.height);
        const loc = Vec2.new(x, y);
        if (!self.map.isSolid(loc)) {
            self.player.locs.appendAssumeCapacity(loc);
            // no need to call 'focusPlayer' because there is still only 1 player
            try self.recomputeVisibility();
            break;
        }
    }
}

test "compilation" {
    std.testing.refAllDecls(WorldHash);
    std.testing.refAllDecls(Player);
    std.testing.refAllDecls(Map);
    std.testing.refAllDecls(World);
}
