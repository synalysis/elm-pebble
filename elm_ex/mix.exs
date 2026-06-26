defmodule ElmEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :elm_ex,
      version: "0.1.0",
      elixir: "~> 1.20",
      compilers: [:leex, :yecc] ++ Mix.compilers(),
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        plt_add_apps: [:mix],
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Elm parser, AST, and IR — a reusable frontend for Elm-to-X compilers"
    ]
  end

  defp aliases do
    [
      "test.ts_corpus": ["test --only ts_corpus"],
      "test.ts_corpus_smoke": ["test --only ts_corpus_smoke"]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.ts_corpus": :test,
        "test.ts_corpus_smoke": :test
      ]
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

  # test/support is compiled via elixirc_paths in a full project; expose for mix run helpers.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
