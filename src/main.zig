const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub fn iterator(text: []const u8) Iterator {
    return .{ .text = text, .index = 0 };
}

pub const Iterator = struct {
    text: []const u8,
    index: usize,

    /// byte length
    pub const len = 8;
    pub const Block = [len]u8;
    pub const Int = std.meta.Int(.unsigned, len * 8);
    pub const IntAndNext = struct { int: Int, next: u8 };
    pub fn next(it: *Iterator) ?IntAndNext {
        defer it.index += 1;
        if (it.index + len >= it.text.len) return null;
        return .{
            .int = blockToInt(block(it.text[it.index..][0..len])),
            .next = it.text[it.index + len],
        };
    }

    pub inline fn block(text: []const u8) Block {
        var blk: Block = [1]u8{0} ** len;
        blk[0..].* = text[0..len].*;
        return blk;
    }
};

pub const Follows = struct {
    map: Map = .{},
    count: usize = 0,

    pub const Map = std.ArrayListUnmanaged(Item);
    pub const Item = packed struct {
        char: u8,
        count: u24,
        pub fn format(item: Item, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try writer.print("{c}-{}", .{ item.char, item.count });
        }
    };
    pub fn lessThan(_: void, a: Item, b: Item) bool {
        return b.count < a.count;
    }
};

pub fn intToBlock(int: Iterator.Int) Iterator.Block {
    return @bitCast(Iterator.Block, int);
}
pub fn strToBlock(str: []const u8) Iterator.Block {
    if (str.len < Iterator.len) {
        std.debug.print("error str {s} with len {} too short. expected len {}\n", .{ str, str.len, Iterator.len });
        std.debug.assert(false);
    }
    return @as(Iterator.Block, str[0..Iterator.len].*);
}
pub fn strToInt(str: []const u8) Iterator.Int {
    return @bitCast(Iterator.Int, strToBlock(str));
}
pub fn blockToInt(blk: Iterator.Block) Iterator.Int {
    return @bitCast(Iterator.Int, blk);
}

pub const Model = struct {
    table: Table = .{},
    allocator: mem.Allocator,
    rand: std.rand.Random,

    pub const Table = std.AutoArrayHashMapUnmanaged(Iterator.Block, Follows);

    pub fn init(allocator: mem.Allocator, rand: std.rand.Random) Model {
        return .{ .allocator = allocator, .rand = rand };
    }
    pub fn deinit(self: *Model, allocator: mem.Allocator) void {
        var iter = self.table.iterator();
        while (iter.next()) |*m| m.value_ptr.map.deinit(allocator);
        self.table.deinit(allocator);
    }
    pub fn feed(self: *Model, input: []const u8) !void {
        var iter = iterator(input);
        while (iter.next()) |it| {
            // std.debug.print("{s}-{c}\n", .{ @bitCast(Iterator.Block, it.int), it.next });
            const block = @bitCast(Iterator.Block, it.int);
            const gop = try self.table.getOrPut(self.allocator, block);
            if (!gop.found_existing) gop.value_ptr.* = .{};
            gop.value_ptr.count += 1;
            for (gop.value_ptr.map.items) |*it2| {
                if (it2.char == it.next) it2.count += 1;
            } else try gop.value_ptr.map.append(self.allocator, .{ .char = it.next, .count = 1 });
        }
    }
    pub fn prep(self: *Model) void {
        // sort each follow map by frequency descending so that more frequent come first
        for (self.table.values()) |follows|
            std.sort.sort(Follows.Item, follows.map.items, {}, Follows.lessThan);
    }

    pub fn gen(
        self: *Model,
        writer: anytype,
        options: struct { maxlen: usize, opt_start_block: ?Iterator.Block = null },
    ) !void {
        const start_block = if (options.opt_start_block) |start_block| start_block else blk: {
            const id = self.rand.intRangeLessThan(usize, 0, self.table.count());
            break :blk self.table.keys()[id];
        };
        _ = try writer.write(&start_block);
        var int = @bitCast(Iterator.Int, start_block);
        var i: usize = 0;
        while (i < options.maxlen) : (i += 1) {
            const follows = self.table.get(intToBlock(int)) orelse {
                std.debug.print("current block {s}\n", .{intToBlock(int)});
                @panic("TODO: recover somehow");
            };

            // pick a random item
            var r = self.rand.intRangeAtMost(usize, 0, follows.count);
            const first_follow = follows.map.items[0];
            var c = first_follow.char;
            r -|= first_follow.count;
            // std.debug.print("follows {any} r {}\n", .{ follows.map.items, r });
            for (follows.map.items[1..]) |mit| {
                if (r == 0) break c;
                r -|= mit.count;
                c = mit.char;
            }

            try writer.writeByte(c);
            int >>= 8;
            int |= @as(Iterator.Int, c) << (8 * (Iterator.len - 1));
        }
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allr = arena.allocator();
    const args = try std.process.argsAlloc(allr);
    var prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    var model = Model.init(allr, prng.random());

    for (args[1..]) |arg| {
        const f = try std.fs.cwd().openFile(arg, .{});
        defer f.close();
        var br = std.io.bufferedReader(f.reader());
        const reader = br.reader();
        const input = try reader.readAllAlloc(allr, std.math.maxInt(u32));
        defer allr.free(input);
        try model.feed(input);
    }

    model.prep();
    try model.gen(
        std.io.getStdOut().writer(),
        // .{ .maxlen = 800, .opt_start_block = strToBlock("\ntest \"a") },
        .{ .maxlen = 800 },
    );
}
