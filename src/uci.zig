//! Implements the Universal chess interface
const std = @import("std");
const UCI_COMMAND_MAX_LENGTH = 1024;

/// Note that these are not all uci commands, just the ones
/// that cannot be trivially handled by next_command
pub const CommandTag = enum(u8) {
    // uci commands
    quit,
    newgame,
    // non-standard uci commands
    eval,
    board,
};

pub const Command = union(CommandTag) {
    quit: void,
    newgame: void,
    eval: void,
    board: void,
};

pub const UCIError = error{
    InvalidCommand,
    MissingArgument,
};

var debug: bool = false;

/// Reads commands until it encounters one that cannot be trivially handled.
/// (One that requires more than just printing static information)
/// This complex command is then returned to be handled by the engine.
pub fn next_command() !Command {
    var buffer = [1]u8{0} ** UCI_COMMAND_MAX_LENGTH;
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();

    while (true) {
        const bytes_read = (try stdin.read(&buffer)) - 1;
        const input = buffer[0..bytes_read];
        var parts = std.mem.split(u8, input, " ");
        const command = parts.next().?;
        if (std.mem.eql(u8, command, "uci")) {
            // identify engine
            _ = try stdout.write("id name zigchess\n");
            _ = try stdout.write("id author Alaska\n");
            // send supported options (none)
            // confirm that we implement uci
            _ = try stdout.write("uciok\n");
        } else if (std.mem.eql(u8, command, "debug")) {
            const arg = parts.next() orelse return UCIError.MissingArgument;
            if (std.mem.eql(u8, arg, "on")) {
                debug = true;
            } else if (std.mem.eql(u8, arg, "off")) {
                debug = false;
            }
        } else if (std.mem.eql(u8, command, "quit")) {
            return Command.quit;
        } else if (std.mem.eql(u8, command, "isready")) {
            _ = try stdout.write("readyok\n");
        } else if (std.mem.eql(u8, command, "ucinewgame")) {
            return Command.newgame;
        }
        // non-standard commands
        else if (std.mem.eql(u8, command, "eval")) {
            return Command.eval;
        } else if (std.mem.eql(u8, command, "board")) {
            return Command.board;
        }

        // ignore unknown commands
    }
}
