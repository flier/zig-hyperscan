const std = @import("std");
const hs = @import("hyperscan");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer {
        const leaked = gpa.deinit();

        if (leaked == std.heap.Check.leak) std.log.err("Memory leak detected: {d} bytes", .{leaked});
    }

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <pattern> <input file>\n", .{args[0]});
        return;
    }

    const pattern = args[1];
    const input_file = args[2];

    const db = try hs.Database.compile(pattern, .{});

    const db_info = try db.info(allocator);
    defer allocator.free(db_info);

    std.log.debug("Hyperscan {s} Database size: {d} bytes", .{ db_info, try db.size() });

    var f = try std.fs.cwd().openFile(input_file, .{});
    defer f.close();

    const data = try f.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    std.log.debug("Data size: {d} bytes", .{data.len});

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    std.log.debug("Scratch size: {d} bytes", .{try scratch.size()});

    try db.scan_block(data, .{
        .scratch = scratch,
    });
}
