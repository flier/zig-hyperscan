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

    const opts = try parseOptions(args);

    std.log.debug("Options: {f}", .{opts});

    const db = try hs.Database.compile(opts.pattern, .{
        .mode = if (opts.stream) .Stream else .Block,
        .som_horizon_large = opts.stream,
        .flags = .SomLeftmost,
    });

    const db_info = try db.info(allocator);
    defer allocator.free(db_info);

    std.log.debug("Hyperscan {s} Database size: {d} bytes", .{ db_info, try db.size() });

    const scratch = try db.alloc_scratch();
    defer scratch.deinit();

    std.log.debug("Scratch size: {d} bytes", .{try scratch.size()});

    var f = try std.fs.cwd().openFile(opts.input_file, .{});
    defer f.close();

    if (opts.stream) {
        const stream = try db.open_stream(.{});
        const ctx = Context{
            .patterns = &[_][]const u8{opts.pattern},
        };

        var buf: [4096]u8 = undefined;
        var off: usize = 0;
        var r = f.reader(&buf);

        while (!r.atEnd()) {
            const rd = r.readStreaming(&buf) catch |err| switch (err) {
                error.EndOfStream => break,
                else => return err,
            };
            const data = buf[0..rd];

            try stream.scan(data, .{
                .scratch = scratch,
                .onEvent = onEvent,
                .context = @constCast(&ctx),
            });

            off += rd;
        }

        try stream.close(.{
            .scratch = scratch,
            .onEvent = onEvent,
            .context = @constCast(&ctx),
        });
    } else {
        const data = try f.readToEndAlloc(allocator, std.math.maxInt(usize));
        defer allocator.free(data);

        std.log.debug("Data size: {d} bytes", .{data.len});

        const ctx = Context{
            .patterns = &[_][]const u8{opts.pattern},
            .data = data,
        };

        try db.scan_block(data, .{
            .scratch = scratch,
            .onEvent = onEvent,
            .context = @constCast(&ctx),
        });
    }
}

const Options = struct {
    pattern: []const u8,
    input_file: []const u8,
    stream: bool,

    pub fn format(s: @This(), writer: *std.Io.Writer) !void {
        try writer.print("pattern: {s}, input_file: {s}, stream: {}", .{ s.pattern, s.input_file, s.stream });
    }
};

fn parseOptions(args: []const []const u8) !Options {
    const program = std.fs.path.basename(args[0]);
    var stream = false;
    var idx: usize = 1;

    while (idx < args.len) {
        const arg = args[idx];

        if (arg[0] != '-') {
            break;
        }

        if (std.mem.eql(u8, arg, "-h") | std.mem.eql(u8, arg, "--help")) {
            showUsage(program);
        } else if (std.mem.eql(u8, arg, "-s") | std.mem.eql(u8, arg, "--stream")) {
            stream = true;
        }

        idx += 1;
    }

    if (args.len < idx + 2) {
        showUsage(program);
    }

    return Options{
        .pattern = args[idx],
        .input_file = args[idx + 1],
        .stream = stream,
    };
}

const usage =
    \\Usage: {s} [options] <pattern> <input file>
    \\
    \\Options:
    \\  -h, --help       Show this help message and exit
    \\  -s, --stream     Use streaming mode
    \\
    \\Examples:
    \\  {s} -s foobar input.txt
    \\  {s} /foobar/i input.txt
    \\
;

fn showUsage(program: []const u8) noreturn {
    std.debug.print(usage, .{ program, program, program });

    std.process.exit(0);
}

const Context = struct {
    patterns: []const []const u8,
    data: ?[]const u8 = null,
};

fn onEvent(evt: hs.MatchEvent) hs.MatchAction {
    const ctx: *Context = @ptrCast(@alignCast(evt.context));

    if (ctx.data) |data| {
        std.log.info("Match for pattern #{} `{s}` at offset {}..{}: {s}", .{ evt.id, ctx.patterns[evt.id], evt.from, evt.to, data[evt.from..evt.to] });
    } else {
        std.log.info("Match for pattern #{} `{s}` at offset {}..{}", .{ evt.id, ctx.patterns[evt.id], evt.from, evt.to });
    }

    return .Continue;
}
