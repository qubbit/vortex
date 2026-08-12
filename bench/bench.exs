# Rough, dependency-free benchmarks for the Vortex combinators.
#
# Run from the project root with either:
#
#     mix run bench/bench.exs
#     elixir bench/bench.exs
#
# The script requires the library sources directly so it also works without a
# compiled build. It reports wall-clock time for parsing inputs of growing size;
# with linear-time node accumulation the time-per-element stays roughly flat.

root = Path.expand("..", __DIR__)

unless Code.ensure_loaded?(Combinators) do
  for file <- ~w(state.ex failure.ex combinators.ex parser.ex lisp_parser.ex) do
    Code.require_file(Path.join([root, "lib", file]))
  end
end

time = fn label, fun ->
  {micros, _result} = :timer.tc(fun)
  :io.format("~-40s ~10.2f ms~n", [label, micros / 1000])
end

IO.puts("\n== rep over N digits ==")

for n <- [1_000, 5_000, 20_000, 50_000] do
  input = String.duplicate("7", n)
  digits = Combinators.rep(Combinators.char("0-9"), 0)
  time.("rep digits, n=#{n}", fn -> {_nodes, _state} = digits.(State.new(input)) end)
end

IO.puts("\n== seq of N literals ==")

for n <- [1_000, 5_000, 20_000] do
  input = String.duplicate("a", n)
  grammar = Combinators.seq(List.duplicate(Combinators.str("a"), n))
  time.("seq literals, n=#{n}", fn -> {_nodes, _state} = grammar.(State.new(input)) end)
end

IO.puts("\n== LISP: parse a big flat list ==")

for n <- [1_000, 5_000, 20_000] do
  program = "(" <> Enum.map_join(1..n, " ", &Integer.to_string/1) <> ")"
  time.("LispParser.parse, n=#{n}", fn -> {:ok, _} = LispParser.parse(program) end)
end

IO.puts("")
