![Unit test status badge](https://github.com/wuelle/zigchess/actions/workflows/run-tests.yml/badge.svg)

## Playing the engine.
This is **not** a standalone engine, you need a frontend that implements the [UCI](https://en.wikipedia.org/wiki/Universal_Chess_Interface) interface.
If you don't know any chess GUI's, [PyChess](https://github.com/pychess/pychess) is a good one.

## Non-standard UCI commands
To aid with debugging, the engine supports some commands not defined in the UCI specification

* **board**: display the current board state
* **eval:** return the evaluation of the current position
* **moves:** print all legal moves in the current position

## Development
Mephisto builds on zig version `0.9.1`. Other versions *may* work, but likely won't due to the rapid
development of the language.
A neat trick for debugging is creating a file with a sequence of uci commands and then 
`cat commands.txt | ./zig-out/bin/zigchess`.

### Tests
Run all unit tests using `zig build test`.

## Ressources
* [FEN position creator](http://www.netreal.de/Forsyth-Edwards-Notation/index.php)
* [Bitboard creator](https://gekomad.github.io/Cinnamon/BitboardCalculator/)
* [Guide to fast legal move generation](https://www.codeproject.com/Articles/5313417/Worlds-fastest-Bitboard-Chess-Movegenerator)
