defmodule Elmc.Backend.Bytecode.ManifestProgram do
  @moduledoc """
  Load and run linked bytecode programs from an on-disk manifest.

  Unlike `Bytecode.Program`, this does not require IR/`decl_map` — it reloads
  encoded sections from `.elmc-build/bytecode` and dispatches nested `call_fn`
  targets through the shared `plans` map on `Bytecode.Runtime`.
  """

  alias Elmc.Backend.Bytecode.{FnTable, Loader, Lower, Runtime}

  @type entry :: {String.t(), String.t()}

  @type section_map :: %{entry() => Lower.section()}

  @type t :: %{
          build_dir: String.t(),
          manifest: map(),
          sections: section_map()
        }

  @spec load(String.t()) :: {:ok, t()} | {:error, term()}
  def load(build_dir) when is_binary(build_dir) do
    manifest_path = Path.join(build_dir, "bytecode/elmc_bytecode.manifest.json")

    with {:ok, manifest} <- Loader.load_manifest(manifest_path),
         {:ok, sections} <- load_all_sections(build_dir, manifest) do
      {:ok, %{build_dir: build_dir, manifest: manifest, sections: sections}}
    end
  end

  @spec load_linked(String.t(), entry()) :: {:ok, t()} | {:error, term()}
  def load_linked(build_dir, root) when is_binary(build_dir) do
    with {:ok, program} <- load(build_dir) do
      {:ok, %{program | sections: link_sections(program.sections, root)}}
    end
  end

  @spec run(t(), entry(), keyword()) :: {:ok, Runtime.value()} | {:error, term()}
  def run(%{sections: sections}, {module, name}, opts \\ []) do
    case Map.fetch(sections, {module, name}) do
      {:ok, section} ->
        Runtime.run_section(
          section,
          Keyword.merge(opts, plans: sections, plan_key: {module, name})
        )

      :error ->
        {:error, :missing_manifest_entry}
    end
  end

  @spec function_entries(t()) :: [map()]
  def function_entries(%{manifest: %{"functions" => functions}}) when is_list(functions),
    do: functions

  def function_entries(_), do: []

  defp load_all_sections(build_dir, %{"functions" => functions}) when is_list(functions) do
    functions
    |> Enum.reduce_while({:ok, %{}}, fn entry, {:ok, acc} ->
      case Loader.load_section(build_dir, entry) do
        {:ok, section} ->
          key = {Map.fetch!(entry, "module"), Map.fetch!(entry, "name")}
          {:cont, {:ok, Map.put(acc, key, section)}}

        {:error, _} = err ->
          {:halt, err}
      end
    end)
  end

  defp load_all_sections(_, _), do: {:error, :invalid_manifest}

  defp link_sections(sections, root) do
    link_sections(sections, [root], %{})
  end

  defp link_sections(_sections, [], acc), do: acc

  defp link_sections(sections, [key | rest], acc) do
    if Map.has_key?(acc, key) do
      link_sections(sections, rest, acc)
    else
      case Map.fetch(sections, key) do
        {:ok, section} ->
          acc = Map.put(acc, key, section)
          next = FnTable.collect_section(section)
          link_sections(sections, rest ++ next, acc)

        :error ->
          link_sections(sections, rest, acc)
      end
    end
  end
end
