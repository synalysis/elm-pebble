defmodule Elmc.Test.WasmRcTrackHarness do
  @moduledoc false

  import ExUnit.Assertions, only: [assert: 1, flunk: 1]

  alias Elmc.Backend.Wasm.ProjectWriter

  @runner_script Path.expand("wasm_probe_runner.mjs", __DIR__)

  @spec compile!(String.t(), String.t(), keyword()) :: :ok
  def compile!(fixture_dir, out_dir, opts \\ []) do
    compile_opts =
      Keyword.merge(
        [
          out_dir: out_dir,
          entry_module: Keyword.get(opts, :entry_module, "Main"),
          strip_dead_code: false,
          plan_ir_mode: :primary,
          targets: [:wasm],
          wasm_strict: false
        ],
        opts
      )

    case Elmc.compile(fixture_dir, compile_opts) do
      {:ok, _} -> :ok
      {:error, reason} -> flunk("wasm compile failed: #{inspect(reason)}")
    end
  end

  @spec wat2wasm!(String.t()) :: String.t()
  def wat2wasm!(out_dir) do
    wat_path = ProjectWriter.wat_path(out_dir)
    wasm_path = Path.join(out_dir, "wasm/app.wasm")
    run_wat2wasm!(wat_path, wasm_path)
    wasm_path
  end

  @spec run_wat2wasm!(String.t(), String.t()) :: :ok
  def run_wat2wasm!(wat_path, wasm_path) do
    case run_wat2wasm(wat_path, wasm_path) do
      :ok -> :ok
      {:error, output} -> flunk("wat2wasm failed:\n#{output}")
    end
  end

  @spec run_wat2wasm(String.t(), String.t()) :: :ok | {:error, String.t()}
  def run_wat2wasm(wat_path, wasm_path) do
    {cmd, prefix_args} = wat2wasm_command()

    {output, code} =
      run_without_ulimit(cmd, prefix_args ++ [wat_path, "-o", wasm_path])

    if code == 0, do: :ok, else: {:error, output}
  end

  @spec run_probe!(String.t(), String.t(), keyword()) :: String.t()
  def run_probe!(out_dir, export_name, opts \\ []) do
    case run_probe(out_dir, export_name, opts) do
      {:ok, output} -> output
      {:error, output} -> flunk("wasm probe runner failed:\n#{output}")
    end
  end

  @spec run_probe(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, String.t()}
  def run_probe(out_dir, export_name, opts \\ []) do
    wat2wasm!(out_dir)
    node = System.find_executable("node") || {:error, "node not available for wasm probe runner"}

    case node do
      {:error, message} ->
        {:error, message}

      node ->
        args =
          [out_dir, export_name] ++
            case Keyword.get(opts, :expected_checksum) do
              nil -> []
              n when is_integer(n) -> [Integer.to_string(n)]
            end

        {output, code} =
          run_without_ulimit(node, [@runner_script | args])

        if code == 0, do: {:ok, output}, else: {:error, output}
    end
  end

  @spec wasm_instantiate_oom?(String.t()) :: boolean()
  def wasm_instantiate_oom?(output) when is_binary(output) do
    output =~ "Out of memory: Cannot allocate Wasm memory"
  end

  @spec assert_balanced_output!(String.t()) :: :ok
  def assert_balanced_output!(output) do
    assert output =~ "rc_ok"
    assert output =~ "checksum="
    :ok
  end

  defp wat2wasm_command do
    cond do
      path = System.find_executable("wat2wasm") ->
        {path, []}

      npx_available?() ->
        {"npx", ["--yes", "--package", "wabt", "wat2wasm"]}

      true ->
        flunk("wat2wasm not available (install wabt or ensure npx can fetch the wabt package)")
    end
  end

  defp npx_available? do
    case System.find_executable("npx") do
      nil -> false
      _ -> true
    end
  end

  defp run_without_ulimit(cmd, args) do
    shell_cmd =
      ("ulimit -v unlimited 2>/dev/null || true; " <>
         Enum.map_join([cmd | args], " ", &quote_shell/1))

    System.cmd("bash", ["-c", shell_cmd], stderr_to_stdout: true)
  end

  defp quote_shell(str), do: "'" <> String.replace(str, "'", "'\\''") <> "'"
end
