defmodule Mix.Tasks.Formatter.Certify do
  @shortdoc "Run formatter certification gates"
  @moduledoc """
  Runs formatter certification gates used by roadmap Phase 12:

      mix formatter.certify --phase A --baseline tmp/parity-baseline.json
      mix formatter.certify --phase C --fixtures /path/to/targeted/fixtures

  This task executes:
  1) parity gate (`mix formatter.parity ...`)
  2) formatter test suite (idempotence/edit-op safety coverage)
  """

  use Mix.Task

  @switches [
    phase: :string,
    baseline: :string,
    fixtures: :string,
    shard_total: :integer,
    shard_index: :integer
  ]

  @impl true
  @spec run(term()) :: term()
  def run(args) do
    Mix.Task.run("app.start")
    {opts, _rest, _invalid} = OptionParser.parse(args, switches: @switches)

    parity_args = build_parity_args(opts)

    Mix.shell().info("formatter_certify: running parity gate")
    Mix.Task.run("formatter.parity", parity_args)

    Mix.shell().info("formatter_certify: running formatter tests")

    Mix.Task.run("test", [
      "test/ide/formatter_test.exs",
      "test/mix/tasks/formatter_parity_task_test.exs"
    ])
  end

  @doc false
  @spec build_parity_args(term()) :: term()
  def build_parity_args(opts) when is_list(opts) do
    []
    |> append_opt("--phase", opts[:phase])
    |> append_opt("--baseline", opts[:baseline])
    |> append_opt("--fixtures", opts[:fixtures])
    |> append_opt("--shard-total", opts[:shard_total])
    |> append_opt("--shard-index", opts[:shard_index])
  end

  @spec append_opt(term(), term(), term()) :: term()
  defp append_opt(args, _flag, nil), do: args
  defp append_opt(args, _flag, ""), do: args
  defp append_opt(args, flag, value), do: args ++ [flag, to_string(value)]
end
