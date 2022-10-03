//! Implements the Universal chess interface
const std = @import("std");

const Level = std.log.Level;
const Scope = std.log.default;
const log = @import("main.zig").log;

const perft = @import("perft.zig");

const board = @import("board.zig");
const parse_fen = board.parse_fen;
const GameState = board.GameState;
const Position = board.Position;
const BoardRights = board.BoardRights;
const Color = board.Color;
const Move = board.Move;

const fixedBufferStream = std.io.fixedBufferStream;
const peekStream = std.io.peekStream;
const Allocator = std.mem.Allocator;

const UCI_COMMAND_MAX_LENGTH = 1024;

fn u32_from_str(str: []const u8) u32 {
    var x: u32 = 0;

    for(str) |c| {
        std.debug.assert('0' <= c);
        std.debug.assert(c <= '9');
        x *= 10;
        x += c - '0';
    }
    return x;
}

/// Reads a block of non-whitespace characters and skips any number of following whitespaces
pub fn read_word(comptime Reader: type, src: Reader) !?[]const u8 {
    var buffer = [1]u8{0} ** 20; // assume no word is longer than 20 bytes
    const word = try src.readUntilDelimiter(&buffer, ' ');

    // skip any number of spaces
    var peekable = peekStream(1, src);
    var b = try peekable.reader().readByte();
    while (b == ' ') {b = try peekable.reader().readByte();}
    try peekable.putBackByte(b);
    return word;
}

const FenError = error {
    missing_field,
};

fn log_command(is_engine: bool, command: []const u8) void {
    if (is_engine) {
        log(Level.info, Scope, "[Engine]:\n\t{s}\n", .{command});
    } else {
        log(Level.info, Scope, "[Gui]:\n\t{s}\n", .{command});
    }
}

/// Reads a block of non-whitespace characters and skips any number of following whitespaces
pub fn read_fen(comptime Reader: type, src: Reader, allocator: Allocator) ![]const u8 {
    return std.mem.concat(allocator, u8, &.{
        (try read_word(Reader, src)) orelse return FenError.missing_field,
        (try read_word(Reader, src)) orelse return FenError.missing_field,
        (try read_word(Reader, src)) orelse return FenError.missing_field,
        (try read_word(Reader, src)) orelse return FenError.missing_field,
        (try read_word(Reader, src)) orelse return FenError.missing_field,
    });
}



/// Note that these are not all uci commands, just the ones
/// that cannot be trivially handled by next_command
pub const GuiCommandTag = enum(u8) {
    // uci commands
    uci,
    isready,
    quit,
    newgame,
    position,
    debug,
    go,
    stop,
    // non-standard uci commands
    eval,
    board,
    moves,
    perft,
};

pub const EngineCommandTag = enum(u8) {
    uciok,
    id,
    readyok,
    bestmove,
    info,
    option,
    report_perft,
};

pub const GuiCommand = union(GuiCommandTag) {
    uci,
    isready,
    quit,
    newgame,
    go: struct {
        ponder: bool,
        btime: ?u32,
        wtime: ?u32,
        binc: u32,
        winc: u32,
        depth: ?u32,
        nodes: ?u32,
        mate: ?u32,
        movetime: ?u32,
        movestogo: ?u32,
        infinite: bool,
    },
    stop,
    eval,
    board,
    moves,
    position: struct {
        active_color: Color,
        state: GameState,
    },
    debug: bool,
    perft: u32,
};

pub const EngineCommand = union(EngineCommandTag) {
    uciok: void,
    id: struct { key: []const u8, value: []const u8 },
    option: struct { 
        name: []const u8, 
        option_type: []const u8, 
        default: ?[]const u8,
        min: ?[]const u8,
        max: ?[]const u8,
        option_var: ?[]const u8,
    },
    readyok: void,
    bestmove: Move,
    info: []const u8,
    report_perft: perft.PerftResult,
};

pub fn send_command(command: EngineCommand, allocator: Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    switch (command) {
        EngineCommandTag.uciok => _ = try stdout.write("uciok\n"),
        EngineCommandTag.id => |keyvalue| _ = try std.fmt.format(stdout, "id {s} {s}\n", keyvalue),
        EngineCommandTag.readyok => _ = try stdout.write("readyok\n"),
        EngineCommandTag.bestmove => |move| {
            const move_name = try move.to_str(allocator);
            _ = try std.fmt.format(stdout, "bestmove {s}\n", .{move_name});
            allocator.free(move_name);
        },
        EngineCommandTag.info => |info| {
            _ = try std.fmt.format(stdout, "info string {s}\n", .{info});
        },
        EngineCommandTag.option => |option| {
            _ = try std.fmt.format(stdout, "option name {s} type {s}", .{option.name, option.option_type});
            if (option.default) |default| {
                _ = try std.fmt.format(stdout, "default {s}", .{default});
            }
            if (option.min) |min| {
                _ = try std.fmt.format(stdout, "min {s}", .{min});
            }
            if (option.max) |max| {
                _ = try std.fmt.format(stdout, "max {s}", .{max});
            }
            if (option.option_var) |option_var| {
                _ = try std.fmt.format(stdout, "var {s}", .{option_var});
            }

        },
        EngineCommandTag.report_perft => |report| {
            const elapsed_nanos = @intToFloat(f64, report.time_elapsed);
            const elapsed_seconds = elapsed_nanos / 1_000_000_000;

            _ = try std.fmt.format(stdout, "{d:.3}s elapsed\n", .{elapsed_seconds});
            _ = try std.fmt.format(stdout, "{} nodes explored\n", .{report.nodes});

            const nps = @intToFloat(f64, report.nodes) / elapsed_seconds;
            if (nps < 1000) {
                _ = try std.fmt.format(stdout, "{d:.3}N/s\n", .{nps});
            } else if (nps < 1_000_000) {
                _ = try std.fmt.format(stdout, "{d:.3}KN/s\n", .{nps / 1000});
            } else {
                _ = try std.fmt.format(stdout, "{d:.3}MN/s\n", .{nps / 1_000_000});
            }
        },
    }
}

pub fn next_command(allocator: Allocator) !GuiCommand {
    var buffer = [1]u8{0} ** UCI_COMMAND_MAX_LENGTH;
    const stdin = std.io.getStdIn().reader();

    read_command: while (true) {
        const input = (try stdin.readUntilDelimiter(&buffer, '\n'));
        log_command(false, input);
        if (input.len == 0) continue;

        var words = std.mem.split(u8, input, " ");
        const command = words.next().?;

        if (std.mem.eql(u8, command, "uci")) {
            return GuiCommand.uci;
        } else if (std.mem.eql(u8, command, "debug")) {
            const arg = words.next().?;
            if (std.mem.eql(u8, arg, "on")) {
                return GuiCommand{ .debug = true };
            } else if (std.mem.eql(u8, arg, "off")) {
                return GuiCommand{ .debug = false };
            } else continue;
        } else if (std.mem.eql(u8, command, "quit")) {
            return GuiCommand.quit;
        } else if (std.mem.eql(u8, command, "isready")) {
            return GuiCommand.isready;
        } else if (std.mem.eql(u8, command, "ucinewgame")) {
            return GuiCommand.newgame;
        } else if (std.mem.eql(u8, command, "go")) {
            var ponder = false;
            var btime: ?u32 = null;
            var wtime: ?u32 = null;
            var binc: u32 = 0;
            var winc: u32 = 0;
            var depth: ?u32 = null;
            var nodes: ?u32 = null;
            var mate: ?u32 = null;
            var movetime: ?u32 = 0;
            var movestogo: ?u32 = null;
            var infinite: bool = false;

            while (words.next()) |arg| {
                // searchmoves

                if (std.mem.eql(u8, arg, "searchmoves")) {
                    unreachable; // unimplemented
                } else if (std.mem.eql(u8, arg, "ponder")) {
                    ponder = true;
                } else if (std.mem.eql(u8, arg, "wtime")) {
                    wtime = u32_from_str(words.next() orelse continue :read_command);
                } else if (std.mem.eql(u8, arg, "btime")) {
                    btime = u32_from_str(words.next() orelse continue :read_command);
                } else if (std.mem.eql(u8, arg, "winc")) {
                    winc = u32_from_str(words.next() orelse continue :read_command);
                } else if (std.mem.eql(u8, arg, "binc")) {
                    binc = u32_from_str(words.next() orelse continue :read_command);
                } else if (std.mem.eql(u8, arg, "movestogo")) {
                    movestogo = u32_from_str(words.next() orelse continue :read_command);
                } else if (std.mem.eql(u8, arg, "depth")) {
                    depth = u32_from_str(words.next() orelse continue :read_command);
                } else if (std.mem.eql(u8, arg, "nodes")) {
                    nodes = u32_from_str(words.next() orelse continue :read_command);
                } else if (std.mem.eql(u8, arg, "mate")) {
                    mate = u32_from_str(words.next() orelse continue :read_command);
                } else if (std.mem.eql(u8, arg, "movetime")) {
                    movetime = u32_from_str(words.next() orelse continue :read_command);
                } else if (std.mem.eql(u8, arg, "infinite")) {
                    infinite = true;
                }
            }

            return GuiCommand{
                .go = .{
                    .ponder = ponder,
                    .wtime = wtime,
                    .btime = btime,
                    .winc = winc,
                    .binc = binc,
                    .depth = depth,
                    .nodes = nodes,
                    .mate = mate,
                    .movetime = movetime,
                    .movestogo = movestogo,
                    .infinite = infinite,
                },
            };
        } else if (std.mem.eql(u8, command, "stop")) {
            return GuiCommand.stop;
        } else if (std.mem.eql(u8, command, "position")) {
            const pos_variant = words.next().?;
            var active_color: Color = undefined;
            var state: GameState = undefined;
            var maybe_moves_str: ?[]const u8 = null;
            if (std.mem.eql(u8, pos_variant, "fen")) {
                // this part gets a bit messy - we concatenate the rest of the uci line, then split it on "moves"
                var parts = std.mem.split(u8, words.rest(), "moves");
                const fen = std.mem.trim(u8, parts.next().?, " ");
                const result = try parse_fen(fen);
                active_color = result.active_color;
                state = result.state;

                const remaining = parts.rest();
                if (remaining.len != 0) {
                    maybe_moves_str = remaining;
                }

            } else if (std.mem.eql(u8, pos_variant, "startpos")) {
                active_color = Color.white;
                state = GameState.initial();
                if (words.next()) |keyword| {
                    if (std.mem.eql(u8, keyword, "moves")) {
                        maybe_moves_str = words.rest();
                    }
                }
            } else { continue; }

            if (maybe_moves_str) |moves_str| {
                var moves = std.mem.split(u8, std.mem.trim(u8, moves_str, " "), " ");
                while (moves.next()) |move_str| {
                    const move = Move.from_str(move_str, allocator, active_color, state) catch continue :read_command;
                    switch (active_color) {
                        Color.white => {
                            state = state.make_move(Color.white, move);
                        },
                        Color.black => {
                            state = state.make_move(Color.black, move);
                        },
                    }
                    active_color = active_color.other();
                }
            }
            return GuiCommand{ .position = .{ .active_color = active_color, .state = state } };
        }
        // non-standard commands
        else if (std.mem.eql(u8, command, "eval")) {
            return GuiCommand.eval;
        } else if (std.mem.eql(u8, command, "board")) {
            return GuiCommand.board;
        } else if (std.mem.eql(u8, command, "moves")) {
            return GuiCommand.moves;
        } else if (std.mem.eql(u8, command, "perft")) {
            const depth = u32_from_str(words.next() orelse "3");
            return GuiCommand{ .perft = depth };
        }

        // ignore unknown commands
    }
}
