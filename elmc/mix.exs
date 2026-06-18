defmodule Elmc.MixProject do
  use Mix.Project

  def project do
    [
      app: :elmc,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: Elmc.CLI],
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [:mix],
        flags: [:error_handling, :unmatched_returns]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Elmc.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elm_ex, path: "../elm_ex"},
      {:elmx, path: "../elmx", only: :test},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp aliases do
    [
      "test.rc": ["test --only rc_track"],
      "test.rc_gate": ["test --only rc_track_gate"],
      "test.rc_stress": ["test --only rc_track_stress"],
      "test.corpus": ["test --only corpus"],
      "test.corpus_smoke": ["test --only corpus_smoke"],
      "test.corpus_index": ["test --only corpus_index"],
      "test.corpus_run": ["test --only corpus_run"],
      "test.corpus_run_smoke": ["test --only corpus_run_smoke"],
      "test.corpus_parity": ["test --only corpus_parity"]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "test.rc": :test,
        "test.rc_gate": :test,
        "test.rc_stress": :test,
        "test.corpus": :test,
        "test.corpus_smoke": :test,
        "test.corpus_index": :test,
        "test.corpus_run": :test,
        "test.corpus_run_smoke": :test,
        "test.corpus_parity": :test
      ]
    ]
  end
end
