const std = @import("std");

const clap = @import("clap");
const hs = @import("hyperscan");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const allocator = gpa.allocator();
    defer {
        _ = gpa.deinit();
    }

    var buf: [std.heap.pageSize()]u8 = undefined;

    // Parse command line arguments
    var opts = try Options.parse(allocator, &buf);
    defer opts.deinit(allocator);

    // Compile patterns into a database
    var db: hs.Database = try .compileMulti(opts.patterns.items, .{
        .mode = if (opts.stream) .{ .stream = true, .som_horizon_large = true } else .{ .block = true },
    });
    defer db.deinit();

    // Get database information
    const db_info = try db.info(allocator);
    defer allocator.free(db_info);

    std.log.debug("Hyperscan {s} Database size: {d} bytes", .{ db_info, try db.size() });

    // Allocate scratch space for scanning
    var scratch = try db.allocScratch();
    defer scratch.deinit();

    // Scan input file
    if (opts.stream) {
        try scanStream(opts.input_file, opts.patterns.items, &buf, db, scratch);
    } else {
        try scanBlock(allocator, opts.input_file, &buf, opts.patterns.items, db, scratch);
    }
}

const Options = struct {
    stream: bool,
    patterns: std.ArrayList(hs.Pattern),
    input_file: std.fs.File,

    fn deinit(self: *Options, allocator: std.mem.Allocator) void {
        self.patterns.deinit(allocator);
        self.input_file.close();
    }

    fn parse(allocator: std.mem.Allocator, buf: []u8) !Options {
        const params = comptime clap.parseParamsComptime(
            \\-h, --help                Display this help and exit.
            \\-s, --stream              Use streaming mode.
            \\<PATTERN>...              Regular expression patterns.
            \\<INPUT_FILE>              Input file.
        );

        var diag = clap.Diagnostic{};
        var res = clap.parse(clap.Help, &params, comptime .{
            .PATTERN = clap.parsers.string,
            .INPUT_FILE = clap.parsers.string,
        }, .{
            .diagnostic = &diag,
            .allocator = allocator,
        }) catch |err| {
            // Report useful error and exit.
            try diag.reportToFile(.stdout(), err);
            return err;
        };
        defer res.deinit();

        const exprs, const input_file = res.positionals;

        if (res.args.help != 0 or exprs.len == 0 or input_file == null) {
            const stdout = std.fs.File.stdout();
            var writer = stdout.writer(buf);
            var out = &writer.interface;

            if (res.exe_arg) |program| {
                try out.print("Usage: {s} ", .{std.fs.path.basename(program)});
            }

            try clap.usage(out, clap.Help, &params);
            try out.print("\n\nOptions:\n\n", .{});
            try clap.help(out, clap.Help, &params, .{});
            try out.flush();

            std.process.exit(0);
        }

        return .{
            .stream = res.args.stream != 0,
            .patterns = try parsePatterns(allocator, exprs),
            .input_file = if (input_file) |file| try std.fs.cwd().openFile(file, .{}) else std.fs.File.stdin(),
        };
    }

    fn parsePatterns(allocator: std.mem.Allocator, exprs: []const []const u8) !std.ArrayList(hs.Pattern) {
        var patterns: std.ArrayList(hs.Pattern) = try .initCapacity(allocator, exprs.len);

        for (exprs) |expr| {
            var pattern = try hs.Pattern.parse(expr);

            pattern.flags.som_leftmost = true;

            try patterns.append(allocator, pattern);
        }

        return patterns;
    }
};

fn scanBlock(allocator: std.mem.Allocator, f: std.fs.File, buf: []u8, patterns: []const hs.Pattern, db: hs.Database, scratch: hs.Scratch) !void {
    var reader = f.reader(buf);
    const data = try reader.interface.allocRemaining(allocator, .unlimited);
    defer allocator.free(data);

    std.log.debug("Data size: {d} bytes", .{data.len});

    const ctx = Context{
        .patterns = patterns,
        .data = data,
    };

    try db.scanBlock(data, scratch, .{
        .onEvent = onEvent,
        .context = @constCast(&ctx),
    });
}

fn scanStream(f: std.fs.File, patterns: []const hs.Pattern, buf: []u8, db: hs.Database, scratch: hs.Scratch) !void {
    const ctx = Context{
        .patterns = patterns,
    };

    var reader = f.readerStreaming(buf);

    try db.scanStream(&reader.interface, scratch, .{
        .onEvent = onEvent,
        .context = @constCast(&ctx),
    });
}

const Context = struct {
    patterns: []const hs.Pattern,
    data: ?[]const u8 = null,
};

fn onEvent(evt: hs.MatchEvent) !void {
    const ctx = evt.data(Context);

    if (evt.from) |from| {
        if (ctx.data) |data| {
            std.log.info("Match for pattern #{} `{f}` at offset {}..{}: {s}", .{ evt.id, ctx.patterns[evt.id], from, evt.to, data[from..evt.to] });
        } else {
            std.log.info("Match for pattern #{} `{f}` at offset {}..{}", .{ evt.id, ctx.patterns[evt.id], from, evt.to });
        }
    } else {
        std.log.info("Match for pattern #{} `{f}` at offset ..{}", .{ evt.id, ctx.patterns[evt.id], evt.to });
    }
}
