const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub fn Iterator(comptime byte_len: comptime_int) type {
    return struct {
        text: []const u8,
        index: isize,

        /// byte length
        pub const len = byte_len;
        pub const Block = [len]u8;
        pub const Int = std.meta.Int(.unsigned, len * 8);
        pub const IntAndNext = struct { int: Int, next: u8 };
        const Self = @This();
        pub fn next(it: *Self) ?IntAndNext {
            defer it.index += 1;
            if (it.index + len >= it.text.len) return null;
            const start = std.math.cast(usize, it.index) orelse 0;
            const end = @bitCast(usize, it.index + len);
            return .{
                .int = strToInt(it.text[start..end]),
                .next = it.text[end],
            };
        }

        pub fn intToBlock(int: Int) Block {
            return @bitCast(Block, int);
        }
        pub fn strToBlock(str: []const u8) Block {
            // if (@import("builtin").mode == .Debug and str.len < len) {
            //     std.debug.print("error str {s} with len {} too short. expected len {}\n", .{ str, str.len, len });
            //     std.debug.assert(false);
            // }
            // return @as(Block, str[0..len].*);
            // TODO optimize this by ensuring leading len zeroes
            var block: Block = [1]u8{0} ** len;
            mem.copy(u8, block[len - str.len ..], str);
            return block;
        }
        pub fn strToInt(str: []const u8) Int {
            return @bitCast(Int, strToBlock(str));
        }
        pub fn blockToInt(blk: Block) Int {
            return @bitCast(Int, blk);
        }
    };
}

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

pub fn Model(comptime byte_len: comptime_int) type {
    return struct {
        table: Table = .{},
        allocator: mem.Allocator,
        rand: std.rand.Random,

        pub const Iter = Iterator(byte_len);
        pub const Table = std.AutoArrayHashMapUnmanaged(Iter.Block, Follows);
        const Self = @This();

        pub fn init(allocator: mem.Allocator, rand: std.rand.Random) Self {
            return .{ .allocator = allocator, .rand = rand };
        }
        pub fn deinit(self: *Self, allocator: mem.Allocator) void {
            var iter = self.table.iterator();
            while (iter.next()) |*m| m.value_ptr.map.deinit(allocator);
            self.table.deinit(allocator);
        }
        pub fn iterator(text: []const u8) Iter {
            return .{ .text = text, .index = -byte_len + 1 };
        }

        pub fn feed(self: *Self, input: []const u8) !void {
            var iter = iterator(input);
            while (iter.next()) |it| {
                // std.debug.print("{s}-{c}\n", .{ @bitCast(Iter.Block, it.int), it.next });
                const block = @bitCast(Iter.Block, it.int);
                const gop = try self.table.getOrPut(self.allocator, block);
                if (!gop.found_existing) gop.value_ptr.* = .{};
                gop.value_ptr.count += 1;
                for (gop.value_ptr.map.items) |*it2| {
                    if (it2.char == it.next) it2.count += 1;
                } else try gop.value_ptr.map.append(self.allocator, .{ .char = it.next, .count = 1 });
            }
        }
        pub fn prep(self: *Self) void {
            // sort each follow map by frequency descending so that more frequent come first
            for (self.table.values()) |follows|
                std.sort.sort(Follows.Item, follows.map.items, {}, Follows.lessThan);
        }

        pub const GenOptions = struct {
            // maximum number of bytes to generate not including the start block
            maxlen: usize,
            // optinal starting block. if provided, must have len <= to byte_length
            start_block: ?[]const u8 = null,
        };

        /// after using model.feed() and model.prep() this method can be used to generate pseudo random text based on the
        /// previous input to feed().
        pub fn gen(
            self: *Self,
            writer: anytype,
            options: GenOptions,
        ) !void {
            const start_block = if (options.start_block) |start_block| Iter.strToBlock(start_block) else blk: {
                const id = self.rand.intRangeLessThan(usize, 0, self.table.count());
                break :blk self.table.keys()[id];
            };
            _ = try writer.write(&start_block);
            var int = @bitCast(Iter.Int, start_block);
            var i: usize = 0;
            while (i < options.maxlen) : (i += 1) {
                const follows = self.table.get(Iter.intToBlock(int)) orelse {
                    std.debug.print("current block {s} {c}\n", .{ Iter.intToBlock(int), Iter.intToBlock(int) });
                    // TODO recovery idea - do a substring search of self.table.entries for this block
                    // with leading/trailing zeroes trimmed
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
                int |= @as(Iter.Int, c) << (8 * (Iter.len - 1));
            }
        }
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const allr = arena.allocator();
    const args = try std.process.argsAlloc(allr);
    var prng = std.rand.DefaultPrng.init(@bitCast(u64, std.time.milliTimestamp()));
    const M = Model(8);
    var model = M.init(allr, prng.random());

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
        .{ .maxlen = 800, .start_block = "pub fn m" },
        // .{ .maxlen = 800 },
    );
}
