defmodule State do
  defstruct [:string, :offset]

  def new(string) do
    %State{string: string, offset: 0}
  end

  def peek(state, n) do
    String.slice(state.string, state.offset, n)
  end

  def read(state, n) do
    %State{string: state.string, offset: state.offset + n}
  end

  def complete?(state) do
    state.offset == String.length(state.string)
  end
end
