const std = @import("std");
const assert = std.debug.assert;

const util = @import("util.zig");

pub const Command = struct {
    help: ?[]const u8 = null,
    sub: ?*const SubCmdMap = null,
    options: ?*const OptionsMap = null,
    aliases: ?*const ShortMap = null,

    pub const SubCmdMap = std.StaticStringMap(?*const Command);
    pub const OptionsMap = std.StaticStringMap(Option);
    pub const ShortMap = std.EnumMap(ShortAlias, ShortItem);

    pub const ShortItem = union(enum) {
        command: Command,
        alias: usize,
    };

    pub const Option = struct {
        kind: Kind,
        short: ?ShortAlias,
        pub const Kind = enum { flag, value };
    };
};

/// Enum representing all printable ascii characters, which are valid for use as short aliases.
pub const ShortAlias = @Type(.{ .@"enum" = info: {
    var fields_buf: [128]std.builtin.Type.EnumField = undefined;
    var fields_len: usize = 0;
    @setEvalBranchQuota(128);
    for (0..128) |ascii_char| {
        if (!std.ascii.isPrint(ascii_char)) continue;
        fields_buf[fields_len] = .{
            .name = &.{ascii_char},
            .value = ascii_char,
        };
        fields_len += 1;
    }
    break :info .{
        .tag_type = u8,
        .is_exhaustive = true,
        .decls = &.{},
        .fields = fields_buf[0..fields_len],
    };
} });

pub inline fn shortAliasFrom(byte: u8) ?ShortAlias {
    return if (std.ascii.isPrint(byte)) @enumFromInt(byte) else null;
}

inline fn parseCommandAst(comptime src: []const u8) !Command {
    comptime {
        if (src.len == 0) return error.EmptyCommandHelp;
        if (src[src.len - 1] != '\n') return parseCommandAst(src ++ "\n");

        // hack that makes it easier to have a mutable string map at comptime
        var AllSectionsMap = struct {};
        var maybe_nameless_cmd: ?Command = null;

        var index: usize = 0;
        var line_count: usize = 0;

        while (index != src.len) {
            const section_start_line = line_count;
            const section_str = blk: {
                const start = index;
                index += 1;
                const end = while (util.comptimeIndexOfScalarPos(u8, src, index, '#')) |maybe_end| {
                    if (maybe_end == 0) {
                        if (index != 0) unreachable;
                        index += 1;
                        continue;
                    }
                    switch (src[maybe_end - 1]) {
                        '\r' => {
                            if (maybe_end - 1 == 0) { // ^ \r '#'
                                if (index != 1) unreachable;
                                index += 1;
                                continue;
                            }
                            switch (src[maybe_end - 2]) {
                                '\n' => break maybe_end, // \r \n '#'
                                else => {
                                    index += maybe_end + 1;
                                    continue;
                                },
                            }
                        },
                        '\n' => break maybe_end, // \n '#'
                        else => {
                            index = maybe_end + 1;
                            continue;
                        },
                    }
                } else src.len;
                index = end;
                line_count += util.comptimeCountScalar(u8, src[start..end], '\n');
                break :blk util.comptimeTrim(u8, src[start..end], &std.ascii.whitespace) ++ "\n";
            };
            if (section_str.len == 1) {
                if (section_str[section_str.len - 1] != '\n') unreachable;
                continue;
            }

            @compileLog(section_str);

            const maybe_section_name, const cmd = try parseSection(section_start_line, section_str);
            const section_name = maybe_section_name orelse {
                if (maybe_nameless_cmd != null) unreachable;
                maybe_nameless_cmd = cmd;
                continue;
            };

            if (@hasField(AllSectionsMap, section_name)) return @field(anyerror, std.fmt.comptimePrint(
                "Section line {d} duplicates entry '{}'",
                .{ section_start_line, std.zig.fmtEscapes(section_name) },
            ));
            const all_sects_info = @typeInfo(AllSectionsMap).@"struct";
            AllSectionsMap = @Type(.{ .@"struct" = util.emplace(all_sects_info, .{
                .fields = all_sects_info.fields ++ [_]std.builtin.Type.StructField{.{
                    .name = section_name ++ "",
                    .type = Command,
                    .default_value = &cmd,
                    .is_comptime = true,
                    .alignment = 0,
                }},
            }) });
        }

        @compileError("TODO: resolve the linked commands in " ++ std.fmt.comptimePrint("{any}", .{AllSectionsMap{}}));
    }
}

/// If `src[0] == '#'`, it's treated as being after a newline.
/// Handles `"\n\r#"` as a newline.
fn findNextHashtagAtStartOfLine(
    comptime src: []const u8,
    comptime start: usize,
) ?usize {
    comptime {
        var index = start;
        while (true) {
            const curr_idx = util.comptimeIndexOfScalarPos(u8, src, index, '#') orelse return null;
            defer index = curr_idx + 1;

            if (curr_idx == 0) return 0;
            if (src[curr_idx - 1] == '\n') return curr_idx; // \n '#'
            if (src[curr_idx - 1] != '\r') continue;
            if (curr_idx - 1 == 0) return curr_idx; // ^ \r '#'
            const before_cr = ;

            switch (src[curr_idx - 2]) {
                '\n' => break curr_idx, // \r \n '#'
                else => {
                    index += curr_idx + 1;
                    continue;
                },
            }

            switch (src[curr_idx - 1]) {
                '\r' => {},
                '\n' => break curr_idx, // \n '#'
                else => {
                    index = curr_idx + 1;
                    continue;
                },
            }
        } else null;
    }
}

inline fn parseSection(
    comptime section_start_line: usize,
    comptime section_str: []const u8,
) !struct { ?[]const u8, Command } {
    _ = section_str; // autofix
    comptime {
        const index: usize = 0;
        _ = index; // autofix
        // const hashtag = while (util.comptimeFind(.first_index_of_any_from(index), u8, section_str, &.{ '\n', '#' })) {};
        // _ = hashtag; // autofix
        return .{ std.fmt.comptimePrint("{any}", .{section_start_line}), .{} };
    }
}

test {
    _ = @compileLog(parseCommandAst(
        \\# sig
        \\Version: 0.2.0
        \\Author: Syndica & Contributors
        \\
        \\COMMANDS:
        \\ * identity            Get own identity
        \\ * gossip              Run gossip client
        \\ * validator           Run Solana validator
        \\ * shred-collector     Run the shred collector to collect and store shreds
        \\ * snapshot-download   Downloads a snapshot
        \\ * snapshot-validate:
        \\     Validates a snapshot
        \\ * snapshot-create     Loads from a snapshot and outputs to new snapshot alt_{VALIDATOR_DIR}/
        \\ * print-manifest      Prints a manifest file
        \\ * leader-schedule:
        \\     Prints the leader schedule from the snapshot
        \\
        \\OPTIONS:
        \\ -l, --log-level <err|warn|info|debug>   The amount of detail to log (default = debug)
        \\     --metrics-port <port_number>        port to expose prometheus metrics via http - default: 12345
        \\ -h, --help                              Prints help information
        \\
        \\
        \\# sig identity
        \\
        \\Get own identity
        \\
        \\Gets own identity (Pubkey) or creates one if doesn't exist.
        \\
        \\NOTE: Keypair is saved in $HOME/.sig/identity.key.
        \\
        \\OPTIONS:
        \\  -h, --help   Prints help information    
        \\
        \\
        \\# sig gossip
        \\
        \\Run gossip client
        \\
        \\Start Solana gossip client on specified port.
        \\
        \\OPTIONS:
        \\      --gossip-host <Gossip Host>           IPv4 address for the validator to advertise in gossip - default: get from --entrypoint, fallback to 127.0.0.1
        \\  -p, --gossip-port <Gossip Port>           The port to run gossip listener - default: 8001
        \\  -e, --entrypoint <Entrypoints>            gossip address of the entrypoint validators
        \\      --spy-node                            run as a gossip spy node (minimize outgoing packets)
        \\      --dump-gossip                         periodically dump gossip table to csv files and logs
        \\  -n, --network <Network for Entrypoints>   network to use with predefined entrypoints
        \\  -h, --help                                Prints help information
    ));
}
