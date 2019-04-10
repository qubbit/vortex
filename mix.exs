defmodule Vortex.MixProject do
  use Mix.Project

  @maintainers ["Gopal Adhikari"]
  @url "https://github.com/qubbit/vortex"

  def project do
    [
      app: :vortex,
      description: "A parser combinator library for Elixir",
      package: package(),
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      {:ex_doc, ">= 0.19.1", only: [:dev], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: @maintainers,
      licenses: ["MIT"],
      links: %{Github: @url},
      files: ~w(lib LICENSE mix.exs README.md)
    ]
  end
end
