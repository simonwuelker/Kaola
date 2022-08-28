![Unit test status badge](https://github.com/wuelle/zigchess/actions/workflows/run-tests.yml/badge.svg)

## Playing the engine.
This is **not** a standalone engine, you need a frontend that implements the [UCI](https://en.wikipedia.org/wiki/Universal_Chess_Interface) interface.
If you don't know any chess GUI's, [PyChess](https://github.com/pychess/pychess) is a good one.

## Non-standard UCI commands
To aid with debugging, the engine supports some commands not defined in the UCI specification

* **board**: display the current board state
* **eval:** return the evaluation of the current position

## Development

### Tests
Run all unit tests using `zig build test`.

## Ressources
* [FEN position creator](http://www.netreal.de/Forsyth-Edwards-Notation/index.php)
* [Bitboard creator](https://gekomad.github.io/Cinnamon/BitboardCalculator/)
* [Guide to fast legal move generation](https://www.codeproject.com/Articles/5313417/Worlds-fastest-Bitboard-Chess-Movegenerator)
