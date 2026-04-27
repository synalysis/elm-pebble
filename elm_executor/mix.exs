defmodule ElmExecutor.MixProject do
  use Mix.Project

  def project do
    [
      app: :elm_executor,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: [main_module: ElmExecutor.CLI]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
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
