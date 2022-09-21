const std = @import("std");
const ArrayList = std.ArrayList;
const Level = std.log.Level;
const Scope = std.log.default;
const OpenMode = std.fs.File.OpenMode;

const bitboard = @import("bitboard.zig");

const board = @import("board.zig");
const Move = board.Move;
const GameState = board.GameState;
const Color = board.Color;

const generate_moves = @import("movegen.zig").generate_moves;

const searcher = @import("searcher.zig");
const pesto = @import("pesto.zig");

const uci = @import("uci.zig");
const GuiCommand = uci.GuiCommand;
const EngineCommand = uci.EngineCommand;
const send_command = uci.send_command;

const perft = @import("perft.zig").perft;

const bitops = @import("bitops.zig");

const LOG_FILE = "logs";

pub fn init() !void {
    std.fs.cwd().deleteFile(LOG_FILE) catch {}; // if the file doesn't exist, thats fine
    _ = try std.fs.cwd().createFile(LOG_FILE, .{});
    bitboard.init_magics();
    // bitboard.init_slider_attacks();
    // bitboard.init_paths_between_squares(); // depends on initialized slider attacks
    pesto.init_tables();
}

pub fn log(comptime message_level: Level, comptime scope: anytype, comptime format: []const u8, args: anytype) void {
    _ = scope;
    _ = message_level;
    const file = std.fs.cwd().openFile(LOG_FILE, .{.mode = OpenMode.write_only}) catch unreachable;
    file.seekFromEnd(0) catch unreachable;
    _ = std.fmt.format(file.writer(), format, args) catch unreachable;
    file.close();
}

pub fn main() !void {
    std.debug.print("has pext: {}\n", .{bitops.has_pext()});
    std.debug.print("pext(1, 1): {}\n", .{bitops.pext(1, 1)});
    // var rook_table: [0x19000]u64 = undefined;
    // const slice = rook_table[3..10];
    // std.debug.print("len {d}\n", .{slice.len});
    // const slice2 = slice[0..4];
    // std.debug.print("len {d}\n", .{slice2.len});
    // const Instant = std.time.Instant;

    // var min_time: u64 = ~@as(u64, 0);
    // var min_seed: u64 = 0;

    // const bishop_seed = 6826;
    // _ = bishop_seed;

    // var i: u64 = 1;
    // while(i < 10000): (i += 1) {
    //     if (i % 100 == 0) {
    //         std.debug.print("{d}\n", .{i});
    //     }
    //     const start = try Instant.now();
    //     bitboard.init_magics(i);
    //     const end = try Instant.now();
    //     const elapsed = end.since(start);
    //     if (elapsed < min_time) {
    //         min_time = elapsed;
    //         min_seed = i;
    //     }
    // }
    // std.debug.print("minimal time: {d:.3}ms\n", .{@intToFloat(f64, min_time / 1_000_000)});
    // std.debug.print("best seed: {d}\n", .{min_seed});

    // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    // defer std.debug.assert(!gpa.deinit());
    // var allocator = gpa.allocator();

    // try init();
    // _ = allocator;

    // _ = allocator;
    // const Square = board.Square;
    // const Bitboard = bitboard.Bitboard;

    // std.debug.print("================", .{});
    // const blocked: Bitboard = 0xfdfe040044229bf7;
    // bitboard.print_bitboard(blocked, "blocked");

    // bitboard.print_bitboard(bitboard.bishop_attacks(Square.E4, blocked), "rook attacks");


    // will probably be overwritten by "ucinewgame" but it prevents undefined behaviour
    // just define a default position
    // var active_color = Color.white;
    // var state = GameState.initial();
    // mainloop: while (true) {
    //     const command = try uci.next_command(allocator);
    //     try switch (command) {
    //         GuiCommand.uci => {
    //             try send_command(EngineCommand{ .id = .{ .key = "name", .value = "Mephisto" } }, allocator);
    //             try send_command(EngineCommand{ .id = .{ .key = "author", .value = "Alaska" } }, allocator);
    //             try send_command(EngineCommand.uciok, allocator);
    //         },
    //         GuiCommand.isready => send_command(EngineCommand.readyok, allocator),
    //         GuiCommand.debug => {},
    //         GuiCommand.newgame => {
    //             active_color = Color.white;
    //             state = GameState.initial();
    //         },
    //         GuiCommand.position => |game| {
    //             active_color = game.active_color;
    //             state = game.state;
    //         },
    //         GuiCommand.go => {
    //             const best_move = try searcher.search(active_color, state, 3, allocator);
    //             try send_command(EngineCommand{ .bestmove = best_move }, allocator);
    //         },
    //         GuiCommand.stop => {},
    //         GuiCommand.board => state.print(),
    //         GuiCommand.eval => {
    //             switch (active_color) {
    //                 Color.white => std.debug.print("{d}\n", .{pesto.evaluate(Color.white, state.position)}),
    //                 Color.black => std.debug.print("{d}\n", .{pesto.evaluate(Color.black, state.position)}),
    //             }
    //         },
    //         GuiCommand.moves => {
    //             var move_list = ArrayList(Move).init(allocator);
    //             defer move_list.deinit();

    //             switch (active_color) {
    //                 Color.white => try generate_moves(Color.white, state, &move_list),
    //                 Color.black => try generate_moves(Color.black, state, &move_list),
    //             }
    //             

    //             for (move_list.items) |move| {
    //                 const move_name = try move.to_str(allocator);
    //                 std.debug.print("{s}\n", .{move_name});
    //                 allocator.free(move_name);
    //             }
    //         },
    //         GuiCommand.perft => |depth| {
    //             const report = try perft(active_color, state, allocator, @intCast(u8, depth));
    //             try send_command(EngineCommand{ .report_perft = report }, allocator);
    //         },
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
    try init(); // setup for tests

    // reference other tests in here
    _ = @import("movegen.zig");
    _ = @import("bitops.zig");
}
