//! Implements the Universal chess interface
const std = @import("std");

const board = @import("board.zig");
const Position = board.Position;
const BoardRights = board.BoardRights;
const Color = board.Color;
const Move = board.Move;

const fixedBufferStream = std.io.fixedBufferStream;
const peekStream = std.io.peekStream;
const Allocator = std.mem.Allocator;

const UCI_COMMAND_MAX_LENGTH = 1024;

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
};

pub const EngineCommandTag = enum(u8) {
    uciok,
    id,
    readyok,
    bestmove,
};

pub const GuiCommand = union(GuiCommandTag) {
    uci,
    isready,
    quit,
    newgame,
    go,
    stop,
    eval,
    board,
    position: struct {
        position: Position,
        board_rights: BoardRights,
    },
    debug: bool,
};

pub const EngineCommand = union(EngineCommandTag) {
    uciok: void,
    id: struct { key: []const u8, value: []const u8 },
    readyok: void,
    bestmove: Move,
};

pub fn send_command(command: EngineCommand, allocator: Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    switch (command) {
        EngineCommandTag.uciok => _ = try stdout.write("uciok\n"),
        EngineCommandTag.id => |keyvalue| _ = try std.fmt.format(stdout, "id {s} {s}\n", keyvalue),
        EngineCommandTag.readyok => _ = try stdout.write("readyok\n"),
        EngineCommandTag.bestmove => |move| _ = try std.fmt.format(stdout, "bestmove {s}\n", .{move.to_str(allocator)}),
    }
}

pub fn next_command(allocator: Allocator) !GuiCommand {
    var buffer = [1]u8{0} ** UCI_COMMAND_MAX_LENGTH;
    const stdin = std.io.getStdIn().reader();
    _ = allocator;

    while (true) {
        const input = (try stdin.readUntilDelimiter(&buffer, '\n'));
        if (input.len == 0) continue;

        // var reader = fixedBufferStream(input).reader();
        // const command = (try read_word(@TypeOf(reader), reader)) orelse continue;
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
            return GuiCommand.go;
        } else if (std.mem.eql(u8, command, "stop")) {
            return GuiCommand.stop;
        } else if (std.mem.eql(u8, command, "position")) {
            const pos_variant = words.next().?;
            var position: Position = undefined;
            var board_rights: BoardRights = undefined;
            var maybe_moves_str: ?[]const u8 = null;
            if (std.mem.eql(u8, pos_variant, "fen")) {
                // this part gets a bit messy - we concatenate the rest of the uci line, then split it on "moves"
                var parts = std.mem.split(u8, words.rest(), "moves");
                const fen = std.mem.trim(u8, parts.next().?, " ");
                const seperator = std.mem.indexOf(u8, fen, " ").?;
                position = Position.from_fen(fen[0..seperator]) catch continue;
                board_rights = BoardRights.from_fen(fen[seperator + 1..fen.len]) catch continue;

                const remaining = parts.rest();
                if (remaining.len != 0) {
                    maybe_moves_str = remaining;
                }

            } else if (std.mem.eql(u8, pos_variant, "startpos")) {
                position = Position.starting_position();
                board_rights = BoardRights.initial();
                if (words.next()) |keyword| {
                    if (std.mem.eql(u8, keyword, "moves")) {
                        maybe_moves_str = words.rest();
                    }
                }
            } else { continue; }

            if (maybe_moves_str) |moves_str| {
                var moves = std.mem.split(u8, std.mem.trim(u8, moves_str, " "), " ");
                while (moves.next()) |move_str| {
                    const move = try Move.from_str(move_str, allocator, position, board_rights);// catch continue :read_command;
                    switch (board_rights.active_color) {
                        Color.white => {
                            position = position.make_move(Color.white, move);
                        },
                        Color.black => {
                            position = position.make_move(Color.black, move);
                        },
                    }
                    board_rights.register_move(move);
                }
            }
            return GuiCommand{ .position = .{ .position = position, .board_rights = board_rights } };
        }
        // non-standard commands
        else if (std.mem.eql(u8, command, "eval")) {
            return GuiCommand.eval;
        } else if (std.mem.eql(u8, command, "board")) {
            return GuiCommand.board;
        }

        // ignore unknown commands
    }
}
