//! Implements the Universal chess interface
const std = @import("std");
const UCI_COMMAND_MAX_LENGTH = 1024;

/// Note that these are not all uci commands, just the ones
/// that cannot be trivially handled by next_command
pub const GuiCommandTag = enum(u8) {
    // uci commands
    uci,
    isready,
    quit,
    newgame,
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
    debug: bool,
};

pub const EngineCommand = union(EngineCommandTag) {
    uciok: void,
    id: struct { key: []const u8, value: []const u8 },
    readyok: void,
};

pub fn send_command(command: EngineCommand) !void {
    const stdout = std.io.getStdOut().writer();
    switch (command) {
        EngineCommandTag.uciok => _ = try stdout.write("uciok\n"),
        EngineCommandTag.id => |keyvalue| _ = try std.fmt.format(stdout, "id {s} {s}\n", keyvalue),
        EngineCommandTag.readyok => _ = try stdout.write("readyok\n"),
    }
}

pub fn next_command() !GuiCommand {
    var buffer = [1]u8{0} ** UCI_COMMAND_MAX_LENGTH;
    const stdin = std.io.getStdIn().reader();

    while (true) {
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
