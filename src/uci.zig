//! Implements the Universal chess interface
const std = @import("std");
const board = @import("board.zig");
const Position = board.Position;
const BoardRights = board.BoardRights;
const Color = board.Color;
const Move = board.Move;

const UCI_COMMAND_MAX_LENGTH = 1024;

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

pub fn send_command(command: EngineCommand, allocator: *const std.mem.Allocator) !void {
    const stdout = std.io.getStdOut().writer();
    switch (command) {
        EngineCommandTag.uciok => _ = try stdout.write("uciok\n"),
        EngineCommandTag.id => |keyvalue| _ = try std.fmt.format(stdout, "id {s} {s}\n", keyvalue),
        EngineCommandTag.readyok => _ = try stdout.write("readyok\n"),
        EngineCommandTag.bestmove => |move| _ = try std.fmt.format(stdout, "bestmove {s}\n", .{move.to_str(allocator)}),
    }
}

pub fn next_command(allocator: *const std.mem.Allocator) !GuiCommand {
    var buffer = [1]u8{0} ** UCI_COMMAND_MAX_LENGTH;
    const stdin = std.io.getStdIn().reader();

    get_command: while (true) {
        const input = (try stdin.readUntilDelimiter(&buffer, '\n'));
        if (input.len == 0) continue;

        var parts = std.mem.split(u8, input, " ");
        const command = parts.next().?;
        if (std.mem.eql(u8, command, "uci")) {
            return GuiCommand.uci;
        } else if (std.mem.eql(u8, command, "debug")) {
            const arg = parts.next() orelse continue;
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
            const position_arg = if (std.mem.indexOf(u8, input, "moves")) |index| poswithmoves: {
                break :poswithmoves std.mem.trim(u8, input[command.len..index], " ");
            } else poswithoutmoves: {
                break :poswithoutmoves std.mem.trim(u8, input[command.len..], " ");
            };
            const fen = if (std.mem.eql(u8, position_arg, "startpos")) default: {
                break :default "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
            } else fen: {
                break :fen position_arg;
            };
            const seperator = std.mem.indexOf(u8, fen, " ").?;
            var position = Position.from_fen(fen[0..seperator]) catch continue :get_command;
            var board_rights = BoardRights.from_fen(fen[seperator + 1..fen.len]) catch continue :get_command;
            if (std.mem.eql(u8, parts.next().?, "moves")) {
                while (parts.next()) |move_str| {
                    std.debug.print("making move {s}\n", .{move_str});
                    const move = Move.from_str(move_str, allocator, position, board_rights) catch continue :get_command;
                    switch (board_rights.active_color) {
                        Color.white => {
                            position = position.make_move(Color.white, move);
                        },
                        Color.black => {
                            position = position.make_move(Color.black, move);
                        },
                    }
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
