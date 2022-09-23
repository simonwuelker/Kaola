![Unit test status badge](https://github.com/wuelle/zigchess/actions/workflows/run-tests.yml/badge.svg)

Kaola is a UCI chess engine. It's in it's early stages, these are some of the features that have
already been implemented:
* ["Fancy" magic bitboards](https://www.chessprogramming.org/Magic_Bitboards#Fancy)
* [PEXT](https://www.felixcloutier.com/x86/pext) magic hashing on x86 machines supportin the `bmi2` instruction set
* alpha beta search

## Playing the engine.
This is **not** a standalone engine, you need a frontend that implements the [UCI](https://en.wikipedia.org/wiki/Universal_Chess_Interface) interface.
If you don't know any chess GUI's, [PyChess](https://github.com/pychess/pychess) is a good one.

## Non-standard UCI commands
To aid with debugging, the engine supports some commands not defined in the UCI specification

| Command           | Description                                   |  
| ----------------- | --------------------------------------------- |
| **board**         | display the current board state               |
| **eval**          | return the evaluation of the current position |
| **moves**         | print all legal moves in the current position |
| **perft [depth]** | benchmark movegen in current position         |

## Development
Kaola builds on zig version `0.10.0`. Other versions *may* work, but likely won't due to the rapid
development of the language.

The custom panic handler is disabled until [#12935](https://github.com/ziglang/zig/issues/12935) is closed.

A neat trick for debugging is creating a file with a sequence of uci commands and then 
`cat commands.txt | ./zig-out/bin/kaola`.

### Tests
Run all unit tests using `zig build test`.

## Credits
During development, i looked at various other engines and stole some neat ideas from them.
These include:
* [Gigantua](https://github.com/Gigantua/Gigantua)
* [Stockfish](https://github.com/official-stockfish/Stockfish)
* [Surge](https://github.com/nkarve/surge)
* [Avalanche](https://github.com/SnowballSH/Avalanche)

I also want to thank [Maksim Korzh](https://github.com/maksimKorzh/bbc) for his [Youtube series on bitboard engines](https://www.youtube.com/playlist?list=PLmN0neTso3Jxh8ZIylk74JpwfiWNI76Cs)
which initially inspired me to build my own engine.

## Ressources
* [FEN position creator](http://www.netreal.de/Forsyth-Edwards-Notation/index.php)
* [Bitboard creator](https://gekomad.github.io/Cinnamon/BitboardCalculator/)
* [Guide to fast legal move generation](https://www.codeproject.com/Articles/5313417/Worlds-fastest-Bitboard-Chess-Movegenerator)
