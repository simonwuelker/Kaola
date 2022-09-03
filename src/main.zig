const std = @import("std");
const bitboard = @import("bitboard.zig");
const board = @import("board.zig");
const movegen = @import("movegen.zig");
// const searcher = @import("searcher.zig");
const pesto = @import("pesto.zig");
// const uci = @import("uci.zig");
// const GuiCommand = uci.GuiCommand;
// const EngineCommand = uci.EngineCommand;
// const send_command = uci.send_command;

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

    const pos = try board.Position.from_fen("3r4/1k2P3/1q6/1B4p1/1n6/4R2R/q2R1K2/8");
    try pos.print();
    const board_rights = comptime board.BoardRights.initial();
    const moves = try movegen.generate_moves(board_rights, pos, gpa);
    std.debug.print("found {d} moves\n", .{moves.items.len});
    moves.deinit();

    // const stdout = std.io.getStdOut().writer();
    // // var pos = board.Position.starting_position();
    // _ = pos;
    // try board_rights.print(stdout);
    // const move = board.Move{
    //     .from = board.Square.E7.as_board(),
    //     .to = board.Square.D8.as_board(),
    //     .move_type = board.MoveType{ .promote = board.PieceType.knight },
    // };
    // try pos.print();
    // const new = pos.make_move(board.Color.white, move);
    // try new.print();

    // var game: Board = undefined;
    // mainloop: while (true) {
    //     const command = try uci.next_command();
    //     try switch (command) {
    //         GuiCommand.uci => {
    //             try send_command(EngineCommand{ .id = .{ .key = "name", .value = "Mephisto" } });
    //             try send_command(EngineCommand{ .id = .{ .key = "author", .value = "Alaska" } });
    //             try send_command(EngineCommand.uciok);
    //         },
    //         GuiCommand.isready => send_command(EngineCommand.readyok),
    //         GuiCommand.debug => {},
    //         GuiCommand.newgame => game = Board.starting_position(),
    //         GuiCommand.position => |pos| game = pos,
    //         GuiCommand.go => {
    //             const best_move = searcher.search(game, 3);
    //             try send_command(EngineCommand{ .bestmove = best_move });
    //         },
    //         GuiCommand.stop => {},
    //         GuiCommand.board => game.print(),
    //         GuiCommand.eval => std.debug.print("{d}\n", .{pesto.evaluate(game)}),
    //         GuiCommand.quit => break :mainloop,
    //     };
    // }
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
