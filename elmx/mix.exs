defmodule Elmx.MixProject do
  use Mix.Project

  def project do
    [
      app: :elmx,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      dialyzer: [
        plt_add_apps: [:mix],
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      deps: deps(),
      aliases: aliases(),
      escript: [main_module: Elmx.CLI],
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  defp aliases do
    [
      "test.ts_corpus": ["cmd --cd ../elm_ex mix test.ts_corpus"],
      "test.ts_corpus_smoke": ["cmd --cd ../elm_ex mix test.ts_corpus_smoke"]
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

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      mod: {Elmx.Application, []}
    ]
  end

  defp deps do
    [
      {:elm_ex, path: "../elm_ex"},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end
end
