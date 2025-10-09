//! A structure containing additional parameters related to an expression.

const std = @import("std");

const hs = @cImport({
    @cInclude("hs/hs.h");
});

pub const hs_expr_ext_t = hs.hs_expr_ext_t;

/// The minimum end offset in the data stream at which this expression should match successfully.
min_offset: ?u64 = null,
/// The maximum end offset in the data stream at which this expression should match successfully.
max_offset: ?u64 = null,
/// The minimum match length (from start to end) required to successfully match this expression.
min_length: ?u64 = null,
/// Allow patterns to approximately match within this edit distance.
edit_distance: ?u32 = null,
/// Allow patterns to approximately match within this Hamming distance.
hamming_distance: ?u32 = null,

const Ext = @This();

pub fn value(self: *const Ext) hs.hs_expr_ext_t {
    var flags: u64 = 0;

    if (self.min_offset) |_| {
        flags |= hs.HS_EXT_FLAG_MIN_OFFSET;
    }
    if (self.max_offset) |_| {
        flags |= hs.HS_EXT_FLAG_MAX_OFFSET;
    }
    if (self.min_length) |_| {
        flags |= hs.HS_EXT_FLAG_MIN_LENGTH;
    }
    if (self.edit_distance) |_| {
        flags |= hs.HS_EXT_FLAG_EDIT_DISTANCE;
    }
    if (self.hamming_distance) |_| {
        flags |= hs.HS_EXT_FLAG_HAMMING_DISTANCE;
    }
    if (self.min_offset) |_| {
        flags |= hs.HS_EXT_FLAG_MIN_OFFSET;
    }

    return hs.hs_expr_ext_t{
        .flags = flags,
        .min_offset = self.min_offset orelse 0,
        .max_offset = self.max_offset orelse 0,
        .min_length = self.min_length orelse 0,
        .edit_distance = self.edit_distance orelse 0,
        .hamming_distance = self.hamming_distance orelse 0,
    };
}

test value {
    const empty = Ext{};
    try std.testing.expectEqualDeep(hs.hs_expr_ext_t{
        .flags = 0,
        .min_offset = 0,
        .max_offset = 0,
        .min_length = 0,
        .edit_distance = 0,
        .hamming_distance = 0,
    }, value(&empty));

    const with_min = Ext{ .min_offset = 1 };
    try std.testing.expectEqualDeep(hs.hs_expr_ext_t{
        .flags = hs.HS_EXT_FLAG_MIN_OFFSET,
        .min_offset = 1,
        .max_offset = 0,
        .min_length = 0,
        .edit_distance = 0,
        .hamming_distance = 0,
    }, value(&with_min));

    const with_max = Ext{ .max_offset = 1, .min_length = 1, .min_offset = 1 };
    try std.testing.expectEqualDeep(hs.hs_expr_ext_t{
        .flags = hs.HS_EXT_FLAG_MAX_OFFSET | hs.HS_EXT_FLAG_MIN_OFFSET | hs.HS_EXT_FLAG_MIN_LENGTH,
        .min_offset = 1,
        .max_offset = 1,
        .min_length = 1,
        .edit_distance = 0,
        .hamming_distance = 0,
    }, value(&with_max));
}
