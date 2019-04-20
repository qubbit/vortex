defmodule Parser do
  import Combinators
  import Combinators.Builtin

  def parse(string, grammar) do
    state = State.new(string)
    IO.inspect grammar.(state)

    # {nodes, new_state} = grammar.(state)

    # if new_state && State.complete?(new_state) do
    #   nodes
    # end
  end
end
