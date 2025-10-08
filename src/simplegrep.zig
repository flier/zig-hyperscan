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

    var f = try std.fs.cwd().openFile(input_file, .{});
    defer f.close();

    const data = try f.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(data);

    std.log.debug("Data size: {d} bytes", .{data.len});

    const db = try hs.Database.compile(pattern, .{
        .flags = .SomLeftmost,
    });

    const db_info = try db.info(allocator);
    defer allocator.free(db_info);

    std.log.debug("Hyperscan {s} Database size: {d} bytes", .{ db_info, try db.size() });

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    std.log.debug("Scratch size: {d} bytes", .{try scratch.size()});

    const ctx = Context{
        .patterns = &[_][]const u8{pattern},
        .data = data,
    };

    try db.scan_block(data, .{
        .scratch = scratch,
        .onEvent = onEvent,
        .context = @constCast(&ctx),
    });
}

const Context = struct {
    patterns: []const []const u8,
    data: []const u8,
};

fn onEvent(evt: hs.MatchEvent) hs.MatchAction {
    const ctx: *Context = @ptrCast(@alignCast(evt.context));

    std.log.info("Match for pattern #{} `{s}` at offset {}..{}: {s}", .{ evt.id, ctx.patterns[evt.id], evt.from, evt.to, ctx.data[evt.from..evt.to] });

    return .Continue;
}
