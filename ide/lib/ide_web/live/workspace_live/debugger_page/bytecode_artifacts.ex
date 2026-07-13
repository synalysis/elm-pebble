defmodule IdeWeb.WorkspaceLive.DebuggerPage.BytecodeArtifacts do
  @moduledoc false

  alias Ide.Debugger.BytecodeTypes
  alias IdeWeb.WorkspaceLive.DebuggerPage.ModelMetadata
  alias IdeWeb.WorkspaceLive.DebuggerSupport.Types, as: SupportTypes

  @type runtime :: SupportTypes.execution_model() | nil
  @type summary :: BytecodeTypes.summary() | nil
  @type function_row :: BytecodeTypes.function_row()
  @type smoke_status :: %{
          optional(:target) => {String.t(), String.t()},
          optional(:status) => :ok | :error,
          optional(:text) => String.t(),
          optional(:error) => String.t()
        }

  @type coverage_preview_row :: BytecodeTypes.failed_preview_row()

  @spec summary(runtime()) :: summary()
  def summary(runtime) do
    runtime
    |> ModelMetadata.raw_model()
    |> Map.get("elmc_bytecode_manifest")
    |> normalize_manifest()
  end

  @spec available?(summary()) :: boolean()
  def available?(%{"available" => true}), do: true
  def available?(%{available: true}), do: true
  def available?(_), do: false

  @spec headline(summary()) :: String.t() | nil
  def headline(manifest) when is_map(manifest) do
    if available?(manifest) do
      fn_count = int_field(manifest, "function_count", 0)
      skipped = int_field(manifest, "skipped_count", 0)
      pruned = int_field(manifest, "pruned_count", 0)

      main =
        manifest
        |> Map.get("plan_coverage")
        |> coverage_line("main", "Main")

      reachable =
        manifest
        |> Map.get("plan_coverage")
        |> coverage_line("reachable", "reachable")

      toolchain =
        manifest
        |> Map.get("plan_toolchain")
        |> toolchain_line()

      parts =
        ["#{fn_count} bytecode functions", "#{skipped} skipped"]
        |> then(fn base -> if pruned > 0, do: base ++ ["#{pruned} pruned"], else: base end)
        |> then(fn base -> if toolchain, do: [toolchain | base], else: base end)
        |> then(fn base -> if main, do: base ++ [main], else: base end)
        |> then(fn base -> if reachable, do: base ++ [reachable], else: base end)

      Enum.join(parts, " · ")
    else
      nil
    end
  end

  def headline(_), do: nil

  @spec main_functions(summary()) :: [function_row()]
  def main_functions(manifest) when is_map(manifest) do
    manifest
    |> Map.get("functions", [])
    |> Enum.filter(fn entry ->
      Map.get(entry, "module") == "Main" or Map.get(entry, :module) == "Main"
    end)
    |> Enum.map(&normalize_function_entry/1)
  end

  def main_functions(_), do: []

  @spec format_result(BytecodeTypes.smoke_param()) :: String.t()
  def format_result(result) do
    result
    |> inspect(limit: 8, printable_limit: 240, width: 80)
  end

  @spec smoke_label(smoke_status() | nil) :: String.t() | nil
  def smoke_label(nil), do: nil

  def smoke_label(%{target: {module, name}, status: :ok, text: text}) when is_binary(text) do
    "#{module}.#{name} → #{text}"
  end

  def smoke_label(%{target: {module, name}, status: :error, error: error}) when is_binary(error) do
    "#{module}.#{name} failed: #{error}"
  end

  def smoke_label(_), do: nil

  @spec skipped_preview(summary()) :: [coverage_preview_row()]
  def skipped_preview(manifest) when is_map(manifest) do
    manifest
    |> Map.get("plan_coverage")
    |> case do
      %{"reachable" => %{"failed_preview" => preview}} when is_list(preview) -> preview
      %{reachable: %{failed_preview: preview}} when is_list(preview) -> preview
      %{"main" => %{"failed_preview" => preview}} when is_list(preview) -> preview
      %{main: %{failed_preview: preview}} when is_list(preview) -> preview
      _ -> []
    end
    |> Enum.take(6)
  end

  def skipped_preview(_), do: []

  defp normalize_manifest(%{available: true} = map), do: stringify_keys(map)
  defp normalize_manifest(%{"available" => true} = map), do: map
  defp normalize_manifest(_), do: nil

  defp normalize_function_entry(entry) when is_map(entry) do
    %{
      "module" => Map.get(entry, "module") || Map.get(entry, :module),
      "name" => Map.get(entry, "name") || Map.get(entry, :name)
    }
  end

  defp coverage_line(%{"main" => main}, "main", _label) when is_map(main),
    do: format_coverage(main, "Main")

  defp coverage_line(%{main: main}, "main", _label) when is_map(main),
    do: format_coverage(main, "Main")

  defp coverage_line(%{"reachable" => reachable}, "reachable", label) when is_map(reachable),
    do: format_coverage(reachable, label)

  defp coverage_line(%{reachable: reachable}, "reachable", label) when is_map(reachable),
    do: format_coverage(reachable, label)

  defp coverage_line(coverage, key, label) when is_map(coverage) do
    case Map.get(coverage, key) || Map.get(coverage, String.to_atom(key)) do
      stats when is_map(stats) -> format_coverage(stats, label)
      _ -> nil
    end
  end

  defp coverage_line(_, _, _), do: nil

  defp toolchain_line(%{"mode" => mode, "strict" => true}), do: "plan #{mode} strict"
  defp toolchain_line(%{"mode" => mode}), do: "plan #{mode}"
  defp toolchain_line(%{mode: mode, strict: true}), do: "plan #{mode} strict"
  defp toolchain_line(%{mode: mode}), do: "plan #{mode}"
  defp toolchain_line(_), do: nil

  defp format_coverage(stats, label) do
    lowered = int_field(stats, "lowered", 0)
    total = int_field(stats, "total", 0)
    "#{label} #{lowered}/#{total} lowered"
  end

  defp int_field(map, key, default) do
    case Map.get(map, key) || Map.get(map, String.to_atom(key)) do
      n when is_integer(n) -> n
      _ -> default
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      value = if is_map(v), do: stringify_keys(v), else: v
      {key, value}
    end)
  end
end
