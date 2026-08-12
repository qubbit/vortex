defmodule Mix.Tasks.Lisp do
  @shortdoc "Run a LISP file, or start the Vortex LISP REPL"
  @moduledoc """
  Run a LISP program with the Vortex evaluator.

      mix lisp                     # start an interactive REPL
      mix lisp path/to/file.lisp   # evaluate a file and print the result

  See `Evaluator` for the supported language.
  """
  use Mix.Task

  @impl Mix.Task
  def run([]), do: Evaluator.repl()

  def run([path | _rest]) do
    case Evaluator.eval_file(path) do
      {:ok, value} -> IO.puts(Evaluator.render(value))
      {:error, reason} -> Mix.raise("lisp: #{reason}")
    end
  end
end
