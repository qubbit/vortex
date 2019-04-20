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
      {:ex_doc, ">= 0.19.1", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.6", only: [:dev], runtime: false},
      {:credo, "~> 1.0.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: @maintainers,
      licenses: ["MIT"],
      links: %{Github: @url},
      files: ~w(examples lib LICENSE mix.exs README.md)
    ]
  end
end
