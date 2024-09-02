const std = @import("std");

pub fn comptimeIndexOfScalarPos(
    comptime T: type,
    comptime haystack: []const T,
    comptime start_idx: usize,
    comptime needle: T,
) ?usize {
    comptime {
        if (haystack.len - start_idx == 0) return null;
        const SrcVec = @Vector(haystack.len - start_idx, T);
        const src_vec: SrcVec = haystack[start_idx..].*;

        const matches = src_vec == @as(SrcVec, @splat(needle));
        if (!@reduce(.Or, matches)) return null;

        const IdxVec = @Vector(haystack.len - start_idx, usize);
        const idx_vec: IdxVec = memoizedIota(usize, haystack.len - start_idx).*;

        const filtered = @select(usize, matches, idx_vec, @as(IdxVec, @splat(std.math.maxInt(usize))));
        return start_idx + @reduce(.Min, filtered);
    }
}

pub fn comptimeLastIndexOfScalarPos(
    comptime T: type,
    comptime haystack: []const T,
    comptime needle: T,
) ?usize {
    comptime {
        const reversed = comptimeReverse(T, haystack);
        const rev_idx = comptimeIndexOfScalarPos(T, reversed, 0, needle) orelse return null;
        return haystack.len - 1 - rev_idx;
    }
}

test comptimeLastIndexOfScalarPos {
    try comptime std.testing.expectEqual(null, comptimeLastIndexOfScalarPos(u8, "", ' '));
    try comptime std.testing.expectEqual(null, comptimeLastIndexOfScalarPos(u8, "a", ' '));
    try comptime std.testing.expectEqual(0, comptimeLastIndexOfScalarPos(u8, " ", ' '));
    try comptime std.testing.expectEqual(2, comptimeLastIndexOfScalarPos(u8, " a ", ' '));
    try comptime std.testing.expectEqual(23 - 1, comptimeLastIndexOfScalarPos(u8, ("\t" ** 23) ++ "ab", '\t'));
}

pub fn comptimeIndexOfNotScalarPos(
    comptime T: type,
    comptime haystack: []const T,
    comptime start_idx: usize,
    comptime needle: T,
) ?usize {
    comptime {
        if (haystack.len - start_idx == 0) return null;
        const SrcVec = @Vector(haystack.len - start_idx, T);
        const src_vec: SrcVec = haystack[start_idx..].*;

        const matches = src_vec != @as(SrcVec, @splat(needle));
        if (!@reduce(.Or, matches)) return null;

        const IdxVec = @Vector(haystack.len - start_idx, usize);
        const idx_vec: IdxVec = memoizedIota(usize, haystack.len - start_idx).*;

        const filtered = @select(usize, matches, idx_vec, @as(IdxVec, @splat(std.math.maxInt(usize))));
        return start_idx + @reduce(.Min, filtered);
    }
}

test comptimeIndexOfNotScalarPos {
    try comptime std.testing.expectEqual(null, comptimeIndexOfNotScalarPos(u8, "", 0, ' '));
    try comptime std.testing.expectEqual(null, comptimeIndexOfNotScalarPos(u8, " ", 0, ' '));
    try comptime std.testing.expectEqual(0, comptimeIndexOfNotScalarPos(u8, "a", 0, ' '));
    try comptime std.testing.expectEqual(1, comptimeIndexOfNotScalarPos(u8, " a", 0, ' '));
    try comptime std.testing.expectEqual(0, comptimeIndexOfNotScalarPos(u8, "a a", 0, ' '));
    try comptime std.testing.expectEqual(23, comptimeIndexOfNotScalarPos(u8, ("\t" ** 23) ++ "a", 0, '\t'));
}

pub fn comptimeLastIndexOfNotScalar(
    comptime T: type,
    comptime haystack: []const T,
    comptime needle: T,
) ?usize {
    comptime {
        const reversed = comptimeReverse(T, haystack);
        const rev_idx = comptimeIndexOfNotScalarPos(T, reversed, 0, needle) orelse return null;
        return haystack.len - 1 - rev_idx;
    }
}

test comptimeLastIndexOfNotScalar {
    try comptime std.testing.expectEqual(null, comptimeLastIndexOfNotScalar(u8, "", ' '));
    try comptime std.testing.expectEqual(null, comptimeLastIndexOfNotScalar(u8, " ", ' '));
    try comptime std.testing.expectEqual(0, comptimeLastIndexOfNotScalar(u8, "a", ' '));
    try comptime std.testing.expectEqual(2, comptimeLastIndexOfNotScalar(u8, "a a", ' '));
    try comptime std.testing.expectEqual(1, comptimeLastIndexOfNotScalar(u8, "ab" ++ ("\t" ** 23), '\t'));
}

pub const FindStrat = union(enum) {
    sequence,
    first_index_of_any_start_idx: usize,
    first_index_of_none_start_idx: usize,
    last_index_of_any,
    last_index_of_none,

    pub const first_index_of_any: FindStrat = .{ .first_index_of_any_start_idx = 0 };
    pub inline fn first_index_of_any_from(comptime start_idx: usize) FindStrat {
        comptime return .{ .first_index_of_any_start_idx = start_idx };
    }

    pub const first_index_of_none: FindStrat = .{ .first_index_of_none_start_idx = 0 };
    pub inline fn first_index_of_none_from(comptime start_idx: usize) FindStrat {
        comptime return .{ .first_index_of_none_start_idx = start_idx };
    }
};

/// Combined implementation of slice search algorithms.
/// Optimized for comptime, by (ab)using the non-eval-branch-quota-consuming
/// nature of SIMD vector operations.
/// Complexity: O(n), n = @min(haystack.len, needles.len).
pub fn comptimeFind(
    comptime search_strat: FindStrat,
    comptime T: type,
    comptime haystack: []const T,
    comptime target: []const T,
) ?usize {
    comptime switch (search_strat) {
        .sequence => {
            if (haystack.len == 0) return null;
            if (target.len == 0) return 0;
            if (target.len > haystack.len) return null;

            const SrcVec = @Vector(haystack.len, T);
            const IdxVec = @Vector(haystack.len, usize);
            const BitVec = @Vector(haystack.len, u1);
            const BoolVec = @Vector(haystack.len, bool);

            const src_vec: SrcVec = haystack[0..].*;

            if (target.len == haystack.len) {
                const is_eql = @reduce(.And, src_vec == target[0..].*);
                return if (is_eql) 0 else null;
            }

            const idx_vec: IdxVec = memoizedIota(usize, haystack.len).*;
            const maxint_vec: IdxVec = @splat(std.math.maxInt(usize));

            const start_matches: BoolVec = src_vec == @as(SrcVec, @splat(target[0]));
            var selected_indices: IdxVec = @select(usize, start_matches, idx_vec, maxint_vec);
            var matches_bits: BitVec = @bitCast(start_matches);

            if (target.len != 1) {
                if (target.len == 0) unreachable;

                const mask_indices_base_arr = memoizedIota(i32, haystack.len);
                for (target[1..], 1..) |target_elem, i| {
                    const target_elem_splat: SrcVec = @splat(target_elem);
                    const target_matches: BitVec = @bitCast(src_vec == target_elem_splat);

                    const MaskIndicesVec = @Vector(haystack.len - i, i32);
                    const mask_indices_base: MaskIndicesVec = mask_indices_base_arr[0 .. haystack.len - i].*;
                    const mask_indices_offset: MaskIndicesVec = @splat(i);
                    const mask_indices = mask_indices_base + mask_indices_offset;

                    const mask_left_arr: [haystack.len - i]u1 = @shuffle(u1, target_matches, undefined, mask_indices);
                    const mask_right_arr: [i]u1 = .{@intFromBool(false)} ** i;
                    const mask: BitVec = mask_left_arr ++ mask_right_arr;
                    matches_bits &= mask;

                    const matches: BoolVec = @bitCast(matches_bits);
                    selected_indices = @select(usize, matches, selected_indices, maxint_vec);
                }
            }

            const matches: BoolVec = @bitCast(matches_bits);
            if (!@reduce(.Or, matches)) return null;
            return @reduce(.Min, selected_indices);
        },

        .first_index_of_any_start_idx,
        .first_index_of_none_start_idx,
        .last_index_of_any,
        .last_index_of_none,
        => {
            const real_haystack, //
            const base_idx, //
            const index_must_be_reversed, //
            const inclusion: enum { any, none } //
            = switch (search_strat) {
                .sequence => unreachable,

                .first_index_of_any_start_idx => |start_idx| .{ haystack[start_idx..], start_idx, false, .any },
                .first_index_of_none_start_idx => |start_idx| .{ haystack[start_idx..], start_idx, false, .none },

                .last_index_of_any => .{ comptimeReverse(T, haystack), 0, true, .any },
                .last_index_of_none => .{ comptimeReverse(T, haystack), 0, true, .none },
            };

            if (real_haystack.len == 0) return null;
            if (target.len == 0) return switch (inclusion) {
                .any => null,
                .none => if (index_must_be_reversed) haystack.len - 1 else 0,
            };

            if (real_haystack.len <= target.len) {
                const NeedleVec = @Vector(target.len, T);
                const needle_vec: NeedleVec = target[0..].*;
                return for (real_haystack, 0..) |elem, idx| {
                    const elem_splat: NeedleVec = @splat(elem);
                    const is_match = switch (inclusion) {
                        .any => @reduce(.Or, elem_splat == needle_vec), // equal to any
                        .none => @reduce(.And, elem_splat != needle_vec), // equal to none
                    };
                    if (is_match) {
                        if (index_must_be_reversed) {
                            if (base_idx != 0) unreachable;
                            break haystack.len - 1 - idx;
                        }
                        break base_idx + idx;
                    }
                } else null;
            } else {
                const SrcVec = @Vector(real_haystack.len, T);
                const IdxVec = @Vector(real_haystack.len, usize);
                const BitVec = @Vector(real_haystack.len, u1);
                const BoolVec = @Vector(real_haystack.len, bool);

                const src_vec: SrcVec = real_haystack[0..].*;
                const maxint_vec: IdxVec = @splat(std.math.maxInt(usize));
                const idx_vec: IdxVec = memoizedIota(usize, real_haystack.len).*;

                const matches: BoolVec = matches: {
                    const start_matches: BoolVec = start_matches: {
                        const needle_splat: SrcVec = @splat(target[0]);
                        break :start_matches switch (inclusion) {
                            .any => src_vec == needle_splat,
                            .none => src_vec != needle_splat,
                        };
                    };
                    if (target.len == 1) {
                        break :matches start_matches;
                    }

                    var matches_bits: BitVec = @bitCast(start_matches);
                    for (target[1..]) |needle| {
                        const needle_splat: SrcVec = @splat(needle);
                        const needle_matches: BitVec = switch (inclusion) {
                            .any => @bitCast(src_vec == needle_splat),
                            .none => @bitCast(src_vec != needle_splat),
                        };
                        switch (inclusion) {
                            .any => matches_bits |= needle_matches,
                            .none => matches_bits &= needle_matches,
                        }
                    }
                    break :matches @bitCast(matches_bits);
                };

                if (!@reduce(.Or, matches)) return null;
                const selected_indices = @select(usize, matches, idx_vec, maxint_vec);
                const relative_idx = @reduce(.Min, selected_indices);
                if (index_must_be_reversed) {
                    if (base_idx != 0) unreachable;
                    return haystack.len - 1 - relative_idx;
                }
                return base_idx + relative_idx;
            }
        },
    };
}

test "comptimeFind sequence" {
    @setEvalBranchQuota(100000);
    try comptime std.testing.expectEqual(null, comptimeFind(.sequence, u8, "", ""));
    try comptime std.testing.expectEqual(0, comptimeFind(.sequence, u8, " ", ""));
    try comptime std.testing.expectEqual(0, comptimeFind(.sequence, u8, "  ", "  "));
    try comptime std.testing.expectEqual(1, comptimeFind(.sequence, u8, " ab", "ab"));
    try comptime std.testing.expectEqual(2, comptimeFind(.sequence, u8, "  ab", "ab"));
    try comptime std.testing.expectEqual(5, comptimeFind(.sequence, u8, "  ab abc", "abc"));
    try comptime std.testing.expectEqual(7, comptimeFind(.sequence, u8, "  ab ababc", "abc"));
    try comptime std.testing.expectEqual(7, comptimeFind(.sequence, u8, "  ab ababcabca", "abca"));
    try comptime std.testing.expectEqual(32, comptimeFind(.sequence, u8, (" " ** 32) ++ "|*-+-*|" ++ (" " ** 64), "|*-+-*|"));
    try comptime std.testing.expectEqual(null, comptimeFind(.sequence, u8, (" " ** 32) ++ "|*-*-*|" ++ (" " ** 64), "|*-+-*|" ** 1000));
    try comptime std.testing.expectEqual(null, comptimeFind(.sequence, u8, (" " ** 500) ++ "|*-*-*|" ++ (" " ** 500), "|*-+-*|" ** 1000));
}

test "comptimeFind first_index_of_any" {
    @setEvalBranchQuota(100000);
    try comptime std.testing.expectEqual(null, comptimeFind(.first_index_of_any, u8, "", ""));
    try comptime std.testing.expectEqual(null, comptimeFind(.first_index_of_any, u8, " ", ""));
    try comptime std.testing.expectEqual(0, comptimeFind(.first_index_of_any, u8, "cba", "abc"));
    try comptime std.testing.expectEqual(1, comptimeFind(.first_index_of_any, u8, " bca", "abc"));
    try comptime std.testing.expectEqual(2, comptimeFind(.first_index_of_any, u8, "  ba", "ab"));
    try comptime std.testing.expectEqual(6, comptimeFind(.first_index_of_any, u8, "  5A dcbc", "abc"));
    try comptime std.testing.expectEqual(2, comptimeFind(.first_index_of_any, u8, "  ab ababcabca5", "5bca"));
    try comptime std.testing.expectEqual(32, comptimeFind(.first_index_of_any, u8, (" " ** 32) ++ "|*-+-*|" ++ (" " ** 64), "|*-+-*|"));
    try comptime std.testing.expectEqual(32, comptimeFind(.first_index_of_any, u8, (" " ** 32) ++ "|*-*-*|" ++ (" " ** 64), "|*-+-*|" ** 1000));
    try comptime std.testing.expectEqual(500, comptimeFind(.first_index_of_any, u8, (" " ** 500) ++ "|*-*-*|" ++ (" " ** 500), "|*-+-*|" ** 1000));
}

test "comptimeFind first_index_of_none" {
    @setEvalBranchQuota(100000);
    try comptime std.testing.expectEqual(null, comptimeFind(.first_index_of_none, u8, "", ""));
    try comptime std.testing.expectEqual(null, comptimeFind(.first_index_of_none_from(0), u8, "", ""));
    try comptime std.testing.expectEqual(0, comptimeFind(.first_index_of_none, u8, " ", ""));
    try comptime std.testing.expectEqual(null, comptimeFind(.first_index_of_none, u8, "cba", "abc"));
    try comptime std.testing.expectEqual(0, comptimeFind(.first_index_of_none, u8, " bca", "abc"));
    try comptime std.testing.expectEqual(3, comptimeFind(.first_index_of_none, u8, "bca ", "abc"));
    try comptime std.testing.expectEqual(2, comptimeFind(.first_index_of_none, u8, "ba  ", "ab"));
    try comptime std.testing.expectEqual(2, comptimeFind(.first_index_of_none, u8, "5aDcbc ", "abc5"));
    try comptime std.testing.expectEqual(10, comptimeFind(.first_index_of_none, u8, "ab5babcabc a", "5bca"));
    try comptime std.testing.expectEqual(null, comptimeFind(.first_index_of_none, u8, "ab5babcabca", "5bca"));
    try comptime std.testing.expectEqual("|*-+-*|".len, comptimeFind(.first_index_of_none, u8, "|*-+-*|" ++ " ", "|*-+-*||*-+-*||*-+-*||*-+-*||*-+-*||*-+-*|"));
    try comptime std.testing.expectEqual("|*-+-*|".len, comptimeFind(.first_index_of_none, u8, "|*-*-*|" ++ (" " ** 64), "|*-+-*||*-+-*||*-+-*||*-+-*|"));
    try comptime std.testing.expectEqual(0, comptimeFind(.first_index_of_none, u8, (" " ** 500) ++ "|*-*-*|" ++ (" " ** 500), "|*-+-*|"));
    try comptime std.testing.expectEqual(500 + "|*-+-*|".len, comptimeFind(.first_index_of_none_from(500), u8, (" " ** 500) ++ "|*-*-*|" ++ (" " ** 500), "|*-+-*|"));
}

test "comptimeFind last_index_of_any" {
    @setEvalBranchQuota(100000);
    try comptime std.testing.expectEqual(null, comptimeFind(.last_index_of_any, u8, "", ""));
    try comptime std.testing.expectEqual(null, comptimeFind(.last_index_of_any, u8, " ", ""));
    try comptime std.testing.expectEqual(2, comptimeFind(.last_index_of_any, u8, "cba", "abc"));
    try comptime std.testing.expectEqual(3, comptimeFind(.last_index_of_any, u8, " bca", "abc"));
    try comptime std.testing.expectEqual(3, comptimeFind(.last_index_of_any, u8, "  ba", "ab"));
    try comptime std.testing.expectEqual(8, comptimeFind(.last_index_of_any, u8, "  5A dcbc", "abc"));
    try comptime std.testing.expectEqual(14, comptimeFind(.last_index_of_any, u8, "  ab ababcabca5", "5bca"));
    try comptime std.testing.expectEqual(32 + "|*-+-*|".len - 1, comptimeFind(.last_index_of_any, u8, (" " ** 32) ++ "|*-+-*|" ++ (" " ** 64), "|*-+-*|"));
    try comptime std.testing.expectEqual(32 + "|*-+-*|".len - 1, comptimeFind(.last_index_of_any, u8, (" " ** 32) ++ "|*-*-*|" ++ (" " ** 64), "|*-+-*|" ** 1000));
    try comptime std.testing.expectEqual(500 + "|*-+-*|".len - 1, comptimeFind(.last_index_of_any, u8, (" " ** 500) ++ "|*-*-*|" ++ (" " ** 500), "|*-+-*|" ** 1000));
}

test "comptimeFind last_index_of_none" {
    @setEvalBranchQuota(100000);
    try comptime std.testing.expectEqual(null, comptimeFind(.last_index_of_none, u8, "", ""));
    try comptime std.testing.expectEqual(0, comptimeFind(.last_index_of_none, u8, " ", ""));
    try comptime std.testing.expectEqual(null, comptimeFind(.last_index_of_none, u8, "cba", "abc"));
    try comptime std.testing.expectEqual(0, comptimeFind(.last_index_of_none, u8, " bca", "abc"));
    try comptime std.testing.expectEqual(3, comptimeFind(.last_index_of_none, u8, "bca ", "abc"));
    try comptime std.testing.expectEqual(3, comptimeFind(.last_index_of_none, u8, "ba  ", "ab"));
    try comptime std.testing.expectEqual(5, comptimeFind(.last_index_of_none, u8, "acD5a cbc", "abc5"));
    try comptime std.testing.expectEqual(1, comptimeFind(.last_index_of_none, u8, "a b5babcabca", "5bca"));
    try comptime std.testing.expectEqual(null, comptimeFind(.last_index_of_none, u8, "ab5babcabca", "5bca"));
    try comptime std.testing.expectEqual("|*-+-*|".len, comptimeFind(.last_index_of_none, u8, "|*-+-*|" ++ " ", "|*-+-*||*-+-*||*-+-*||*-+-*||*-+-*||*-+-*|"));
    try comptime std.testing.expectEqual("|*-+-*|".len + 64 - 1, comptimeFind(.last_index_of_none, u8, "|*-*-*|" ++ (" " ** 64), "|*-+-*||*-+-*||*-+-*||*-+-*|"));
    try comptime std.testing.expectEqual(500 + "|*-+-*|".len + 500 - 1, comptimeFind(.last_index_of_none, u8, (" " ** 500) ++ "|*-*-*|" ++ (" " ** 500), "|*-+-*|"));
}

pub fn comptimeCountScalar(
    comptime T: type,
    comptime haystack: []const T,
    comptime needle: T,
) usize {
    comptime {
        const SrcVec = @Vector(haystack.len, u8);
        const LenVec = @Vector(haystack.len, usize);

        const src_vec: SrcVec = haystack[0..].*;
        const needle_splat: SrcVec = @splat(needle);
        const select_mask = src_vec == needle_splat;

        const one_if_selected: LenVec = @splat(1);
        const zero_if_unselected: LenVec = @splat(1);
        const selected = @select(u8, select_mask, one_if_selected, zero_if_unselected);

        return @reduce(.Add, selected);
    }
}

pub fn comptimeTrimStart(
    comptime T: type,
    comptime haystack: []const T,
    comptime needles: []const T,
) []const T {
    const start = comptime comptimeFind(.first_index_of_none, T, haystack, needles) orelse 0;
    comptime return haystack[start..];
}

pub fn comptimeTrimEnd(
    comptime T: type,
    comptime haystack: []const T,
    comptime needles: []const T,
) []const T {
    const end = comptime comptimeFind(.last_index_of_none, T, haystack, needles) orelse return haystack;
    comptime return haystack[0 .. end + 1];
}

pub fn comptimeTrim(
    comptime T: type,
    comptime haystack: []const T,
    comptime needles: []const T,
) []const T {
    const start = comptime comptimeFind(.first_index_of_none, T, haystack, needles) orelse 0;
    const end = comptime comptimeFind(.last_index_of_none, T, haystack, needles) orelse haystack[start..];
    comptime return haystack[start .. end + 1];
}

pub fn comptimeReverse(comptime T: type, comptime slice: []const T) []const T {
    comptime {
        if (slice.len <= 1) return slice;
        const Vec = @Vector(slice.len, i32);
        const len_dec_splat: Vec = @splat(slice.len - 1);
        const len_iota: Vec = memoizedIota(i32, slice.len).*;
        const reversed: [slice.len]T = @shuffle(T, slice[0..].*, undefined, len_dec_splat - len_iota);
        return &reversed;
    }
}

pub inline fn memoizedIota(
    comptime T: type,
    comptime len: usize,
) *const [len]T {
    comptime {
        @setEvalBranchQuota(len);

        const Len = @TypeOf(len);
        const adjusted_len = memoizedIotaAdjustedLen(len);
        if (len != adjusted_len) {
            return memoizedIota(T, adjusted_len)[0..len];
        }

        if ((@bitSizeOf(Len) - @clz(len)) >= 9 or @popCount(len) == @bitSizeOf(Len)) {
            @setEvalBranchQuota(@ctz(len) * 2);
            const IotaVec = @Vector(len >> 1, T);
            const lhs = memoizedIota(T, len >> 1);
            const rhs: [len >> 1]T = @as(IotaVec, lhs.*) + @as(IotaVec, @splat(len >> 1));
            return lhs ++ rhs;
        }

        var result: [len]T = undefined;
        for (&result, 0..) |*elem, i| elem.* = i;
        const copy = result;
        return &copy;
    }
}

fn memoizedIotaAdjustedLen(len: usize) @TypeOf(len) {
    const Len = @TypeOf(len);
    if (len == 0) return 0;
    if (@popCount(len) == 1) return len;
    if (len == std.math.maxInt(Len)) return len;

    const major_bit1_idx = comptime @bitSizeOf(Len) - 1;
    const major_bit1_mask: Len = comptime 1 << major_bit1_idx;

    const major_bit2_idx = comptime @bitSizeOf(Len) - 2;
    const major_bit2_mask: Len = comptime 1 << major_bit1_idx;

    if (len & major_bit1_mask == 0) {
        return @as(Len, 1) << @intCast(@typeInfo(Len).int.bits - @clz(len));
    }
    const hi_bit_idx = @bitSizeOf(Len) - 1 - @clz(len & ~major_bit1_mask);
    const hi_bit_mask: Len = @as(Len, 1) << @intCast(hi_bit_idx);
    if (hi_bit_idx + 1 != major_bit2_idx) {
        return major_bit1_mask | (hi_bit_mask << 1);
    }

    const sub_result = @call(.always_tail, memoizedIotaAdjustedLen, .{len << 2});
    const major_bits_mask = comptime major_bit1_mask | major_bit2_mask;
    return major_bits_mask | (sub_result >> 2);
}

test memoizedIota {
    try std.testing.expect(memoizedIota(u8, 8).ptr != memoizedIota(u8, 9).ptr);
    try std.testing.expectEqual(memoizedIota(u8, 7).ptr, memoizedIota(u8, 8).ptr);
    try std.testing.expectEqual(memoizedIota(usize, 1 << 14).ptr, memoizedIota(usize, (1 << 14) - 1).ptr);
    try std.testing.expectEqual(memoizedIota(usize, 1 << 15).ptr, memoizedIota(usize, (1 << 14) + 1).ptr);
}

pub inline fn comptimeEraseValueType(comptime value: anytype) *const anyopaque {
    const Caster = struct { comptime value: @TypeOf(value) = value };
    comptime return @typeInfo(Caster).@"struct".fields[0].default_value.?;
}

pub inline fn comptimeErasedPtrAs(comptime ptr: *const anyopaque, comptime T: type) T {
    const Caster = @Type(.{ .Struct = .{
        .layout = .auto,
        .backing_integer = null,
        .is_tuple = false,
        .decls = &.{},
        .fields = &.{.{
            .name = "value",
            .type = T,
            .default_value = ptr,
            .alignment = 0,
            .is_comptime = true,
        }},
    } });
    const casted: Caster = .{};
    comptime return casted.value;
}

pub const AnyComptimeValue = struct {
    Type: type,
    value_ptr: *const anyopaque,

    pub inline fn init(comptime value: anytype) AnyComptimeValue {
        comptime {
            var acv: AnyComptimeValue = .{};
            acv.set(value);
            return acv;
        }
    }

    pub inline fn set(comptime acv: *AnyComptimeValue, comptime value: anytype) void {
        comptime acv.* = .{
            .Type = @TypeOf(value),
            .value_ptr = comptimeEraseValueType(value),
        };
    }

    pub inline fn get(comptime acv: AnyComptimeValue) acv.Type {
        comptime return comptimeErasedPtrAs(acv.value_ptr, acv.Type);
    }
};

pub inline fn emplace(value: anytype, new_fields: anytype) @TypeOf(value) {
    var copy = value;
    inline for (@typeInfo(@TypeOf(new_fields)).@"struct".fields) |field| {
        @field(copy, field.name) = @field(new_fields, field.name);
    }
    return copy;
}

pub const ComptimeStringDynMap = struct {
    Entries: type,

    pub const init: ComptimeStringDynMap = .{
        .Entries = @Type(.{ .@"struct" = .{
            .layout = .auto,
            .backing_integer = null,
            .is_tuple = false,
            .decls = &.{},
            .fields = &.{},
        } }),
    };

    pub inline fn contains(comptime csdm: ComptimeStringDynMap, comptime key: []const u8) bool {
        comptime return @hasField(csdm.Entries, key);
    }

    pub inline fn GetType(comptime csdm: ComptimeStringDynMap, comptime key: []const u8) ?type {
        comptime {
            if (!@hasField(csdm.Entries, key)) return null;
            return @TypeOf(@field(csdm.Entries{}, key).value);
        }
    }

    pub inline fn get(comptime csdm: ComptimeStringDynMap, comptime key: []const u8) ?(csdm.GetType(key) orelse noreturn) {
        comptime {
            if (!@hasField(csdm.Entries, key)) return null;
            return @field(csdm.Entries{}, key).value;
        }
    }

    pub inline fn put(comptime csdm: *ComptimeStringDynMap, comptime key: []const u8, comptime value: anytype) void {
        comptime {
            const old_info = @typeInfo(csdm.Entries).@"struct";
            var new_info = old_info;

            if (@hasField(csdm.Entries, key)) {
                const entry = @field(csdm.Entries{}, key);

                var new_fields = old_info.fields[0..].*;
                new_fields[entry.index].type = Entry(@TypeOf(value));
                new_fields[entry.index].default_value = &.{
                    .value = value,
                    .index = entry.index,
                };

                new_info.fields = &new_fields;
            } else {
                const new_fields = old_info.fields ++ &[_]std.builtin.Type.StructField{.{
                    .name = key ++ "",
                    .type = Entry(@TypeOf(value)),
                    .default_value = &@as(Entry(@TypeOf(value)), .{
                        .value = value,
                        .index = old_info.fields.len,
                    }),
                    .is_comptime = true,
                    .alignment = 0,
                }};
                new_info.fields = new_fields;
            }

            csdm.Entries = @Type(.{ .@"struct" = new_info });
        }
    }

    pub inline fn remove(comptime csdm: *ComptimeStringDynMap, comptime key: []const u8) void {
        comptime {
            if (!@hasField(csdm.Entries, key)) return;
            const removed_entry = @field(csdm.Entries{}, key);

            const old_info = @typeInfo(csdm.Entries).@"struct";
            const last_entry_name = old_info.fields[old_info.fields.len - 1].name;
            const last_entry = @field(csdm.Entries{}, last_entry_name);

            const replacement_entry_name = last_entry_name;
            var replacement_entry = last_entry;
            replacement_entry.index = removed_entry.index;

            var new_fields = old_info.fields[0..].*;
            new_fields[removed_entry.index] = .{
                .name = replacement_entry_name,
                .type = Entry(@TypeOf(replacement_entry.value)),
                .default_value = &replacement_entry,
                .is_comptime = true,
                .alignment = 0,
            };

            var new_info = old_info;
            new_info.fields = new_fields[0 .. new_fields.len - 1];
            csdm.Entries = @Type(.{ .@"struct" = new_info });
        }
    }

    inline fn Entry(comptime Value: type) type {
        return struct {
            value: Value,
            index: usize,
        };
    }
};

test ComptimeStringDynMap {
    comptime var csdm: ComptimeStringDynMap = .init;

    try comptime std.testing.expect(!csdm.contains("3"));
    try comptime std.testing.expect(!csdm.contains("5"));

    comptime csdm.put("3", 3);
    comptime csdm.put("5", "5");

    try comptime std.testing.expect(csdm.contains("3"));
    try comptime std.testing.expectEqual(comptime_int, csdm.GetType("3"));
    try comptime std.testing.expectEqual(3, csdm.get("3"));

    try comptime std.testing.expect(csdm.contains("5"));
    try comptime std.testing.expectEqual(*const [1:0]u8, csdm.GetType("5"));
    try comptime std.testing.expectEqual("5", csdm.get("5"));

    comptime csdm.remove("3");

    try comptime std.testing.expect(!csdm.contains("3"));

    try comptime std.testing.expect(csdm.contains("5"));
    try comptime std.testing.expectEqual(*const [1:0]u8, csdm.GetType("5"));
    try comptime std.testing.expectEqual("5", csdm.get("5"));

    comptime csdm.remove("5");

    try comptime std.testing.expect(!csdm.contains("3"));
    try comptime std.testing.expect(!csdm.contains("5"));
}
