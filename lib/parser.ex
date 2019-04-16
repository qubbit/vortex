defmodule Parser do
  import Combinator

  def parser_a | parser_b do
    alt([parser_a, parser_b])
  end

  def parse(string, grammar) do
    state = State.new(string)
    {nodes, new_state} = grammar.(state)

    if new_state && State.complete?(new_state) do
      nodes
    end
  end

  def zero, do: str("0")
  def non_zero_digit, do: chr("1-9")
  def digit, do: zero() | non_zero_digit()
  def digits, do: rep(digit(), 0)
  def sign, do: str("+") | str("-")

  def positive_integer do
    seq([non_zero_digit(), digits()])
  end

  def negative_integer do
    seq([str("-"), non_zero_digit(), digits()])
  end

  def integer do
    alt([zero(), negative_integer(), positive_integer()])
  end
end
