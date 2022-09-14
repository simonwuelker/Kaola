const std = @import("std");
const ArrayList = std.ArrayList;

const bitboard = @import("bitboard.zig");

const board = @import("board.zig");
const Position = board.Position;
const BoardRights = board.BoardRights;
const Color = board.Color;

const movegen = @import("movegen.zig");
const searcher = @import("searcher.zig");
const pesto = @import("pesto.zig");

const uci = @import("uci.zig");
const GuiCommand = uci.GuiCommand;
const EngineCommand = uci.EngineCommand;
const send_command = uci.send_command;

pub fn init() void {
    // bitboard.init_magic_numbers();
    bitboard.init_slider_attacks();
    bitboard.init_paths_between_squares(); // depends on initialized slider attacks
    pesto.init_tables();
}

pub fn main() !void {
    init();
    var general_purpose_allocator = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!general_purpose_allocator.deinit());
    const gpa = general_purpose_allocator.allocator();

    // will probably be overwritten by "ucinewgame" but it prevents undefined behaviour
    // and eases debugging to just define a default position
    var position = Position.starting_position();
    var board_rights = BoardRights.initial();
    mainloop: while (true) {
        const command = try uci.next_command(&gpa);
        try switch (command) {
            GuiCommand.uci => {
                try send_command(EngineCommand{ .id = .{ .key = "name", .value = "Mephisto" } }, &gpa);
                try send_command(EngineCommand{ .id = .{ .key = "author", .value = "Alaska" } }, &gpa);
                try send_command(EngineCommand.uciok, &gpa);
            },
            GuiCommand.isready => send_command(EngineCommand.readyok, &gpa),
            GuiCommand.debug => {},
            GuiCommand.newgame => {
                position = Position.starting_position();
                board_rights = BoardRights.initial();
            },
            GuiCommand.position => |state| {
                position = state.position;
                board_rights = state.board_rights;
            },
            GuiCommand.go => {
                // const best_move = searcher.search(game, 3);
                // try send_command(EngineCommand{ .bestmove = best_move });
            },
            GuiCommand.stop => {},
            GuiCommand.board => position.print(),
            GuiCommand.eval => {
                switch (board_rights.active_color) {
                    Color.white => std.debug.print("{d}\n", .{pesto.evaluate(Color.white, position)}),
                    Color.black => std.debug.print("{d}\n", .{pesto.evaluate(Color.black, position)}),
                }
            },
            GuiCommand.quit => break :mainloop,
        };
    }
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    @setCold(true);
    const stderr = std.io.getStdErr().writer();
    stderr.print("The engine panicked, this is a bug.\nPlease file an issue at https://github.com/Wuelle/zigchess, including the debug information below.\nThanks ^_^\n", .{}) catch std.os.abort();
    const first_trace_addr = @returnAddress();
    std.debug.panicImpl(error_return_trace, first_trace_addr, msg);
}

test {
    init(); // setup for tests

    // reference other tests in here
    _ = @import("movegen.zig");
    _ = @import("bitops.zig");
}
