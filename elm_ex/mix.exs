defmodule ElmEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :elm_ex,
      version: "0.1.0",
      elixir: "~> 1.17",
      compilers: [:leex, :yecc] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elm parser, AST, and IR — a reusable frontend for Elm-to-X compilers"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
