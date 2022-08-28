# Files
| Filename | Contents | 
| -------- | ----------- |
| [`bitboard.zig`](https://github.com/Wuelle/zigchess/blob/main/src/bitboard.zig) | (magic) bitboards, attack tables |
| [`bitops.zig`](https://github.com/Wuelle/zigchess/blob/main/src/bitops.zig) | Utility functions for bit manipulation (`count_bits`, `get_ls1b_index` etc...) |
| [`board.zig`](https://github.com/Wuelle/zigchess/blob/main/src/board.zig) | Game State, FEN Parsing |
| [`magics.zig`](https://github.com/Wuelle/zigchess/blob/main/src/magics.zig) | Hardcoded Bishop/Rook magic numbers |
| [`main.zig`](https://github.com/Wuelle/zigchess/blob/main/src/main.zig) | Entry point, custom panic handler, test collection |
| [`movegen.zig`](https://github.com/Wuelle/zigchess/blob/main/src/movegen.zig) | Generate legal chess moves from a board state |
| [`rand.zig`](https://github.com/Wuelle/zigchess/blob/main/src/rand.zig) | Fast and simple random number generation |
| [`pesto.zig`](https://github.com/Wuelle/zigchess/blob/main/src/pesto.zig) | Position evaluation function [PeSTO](https://www.chessprogramming.org/PeSTO%27s_Evaluation_Function) |
| [`searcher.zig`](https://github.com/Wuelle/zigchess/blob/main/src/searcher.zig) | Searches a position for the best move |
| [`uci.zig`](https://github.com/Wuelle/zigchess/blob/main/src/uci.zig) | Implements the [Universal Chess Interface](https://en.wikipedia.org/wiki/Universal_Chess_Interface) |
