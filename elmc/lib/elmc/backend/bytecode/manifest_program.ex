defmodule Elmc.Backend.Bytecode.ManifestProgram do
  @moduledoc """
  Load and run linked bytecode programs from an on-disk manifest.

  Unlike `Bytecode.Program`, this does not require IR/`decl_map` — it reloads
  encoded sections from `.elmc-build/bytecode` and dispatches nested `call_fn`
  targets through the shared `plans` map on `Bytecode.Runtime`.
  """

  alias Elmc.Backend.Bytecode.{FnTable, Loader, Lower, Runtime}
  alias Elmc.Backend.Plan.Types.FunctionPlan

  alias Elmc.Backend.Bytecode.Artifacts.Types, as: ArtifactTypes

  @type entry :: {String.t(), String.t()}

  @type section_map :: %{entry() => Lower.section()}

  @type t :: %{
          build_dir: String.t(),
          manifest: ArtifactTypes.wire_manifest(),
          sections: section_map(),
          fusion_plans: %{entry() => FunctionPlan.t()}
        }

  @type load_error :: ArtifactTypes.bytecode_load_error()

  @spec load(String.t()) :: {:ok, t()} | {:error, load_error()}
  def load(build_dir) when is_binary(build_dir) do
    manifest_path = Path.join(build_dir, "bytecode/elmc_bytecode.manifest.json")

    with {:ok, manifest} <- Loader.load_manifest(manifest_path),
         {:ok, sections} <- load_all_sections(build_dir, manifest) do
      fusion_plans = load_fusion_plans(manifest)
      {:ok, %{build_dir: build_dir, manifest: manifest, sections: sections, fusion_plans: fusion_plans}}
    end
  end

  @spec load_linked(String.t(), entry()) :: {:ok, t()} | {:error, load_error()}
  def load_linked(build_dir, root) when is_binary(build_dir) do
    with {:ok, program} <- load(build_dir) do
      {:ok, %{program | sections: link_sections(program.sections, root)}}
    end
  end

  @spec run(t(), entry(), keyword()) :: {:ok, Runtime.value()}
  def run(%{sections: sections, fusion_plans: fusion_plans}, {module, name}, opts \\ []) do
    plans = Map.merge(fusion_plans, sections)

    case Map.fetch(sections, {module, name}) do
      {:ok, section} ->
        Runtime.run_section(
          section,
          Keyword.merge(opts, plans: plans, plan_key: {module, name})
        )

      :error ->
        case Map.fetch(fusion_plans, {module, name}) do
          {:ok, plan} -> Runtime.run_function(plan, Keyword.merge(opts, plans: plans))
          :error -> {:error, :missing_manifest_entry}
        end
    end
  end

  @spec function_entries(t()) :: [ArtifactTypes.manifest_function_entry()]
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

  defp load_fusion_plans(%{"fusion_functions" => functions}) when is_list(functions) do
    functions
    |> Enum.map(&fusion_entry_to_plan/1)
    |> Map.new()
  end

  defp load_fusion_plans(_), do: %{}

  @fusion_kinds %{
    "tuple2_case_table" => :tuple2_case_table,
    "filter_map_row_drop" => :filter_map_row_drop,
    "foldl_offset_patch" => :foldl_offset_patch,
    "reverse_foldl_occupied" => :reverse_foldl_occupied,
    "list_indexed_replace" => :list_indexed_replace,
    "list_int_search" => :list_int_search,
    "spawn_tile_chain" => :spawn_tile_chain,
    "union_int_lut" => :union_int_lut,
    "union_string_lut" => :union_string_lut,
    "int_string_lut" => :int_string_lut,
    "list_map_static_index_at" => :list_map_static_index_at,
    "maybe_int_string" => :maybe_int_string,
    "maybe_with_default_pick_slot" => :maybe_with_default_pick_slot,
    "union_case_four_perm" => :union_case_four_perm,
    "union_int_suffix" => :union_int_suffix,
    "row_slice_adjacent_merge" => :row_slice_adjacent_merge,
    "list_concat_reversed_row_slices" => :list_concat_reversed_row_slices,
    "permute_merge_inverse_pipeline" => :permute_merge_inverse_pipeline
  }

  defp fusion_entry_to_plan(%{"module" => module, "name" => name} = entry) do
    params =
      (entry["params"] || [])
      |> Enum.with_index(fn arg, idx ->
        %Elmc.Backend.Plan.Types.Param{name: arg, type: nil, index: idx}
      end)

    kind = Map.fetch!(@fusion_kinds, entry["fusion_kind"])

    plan = %FunctionPlan{
      module: module,
      name: name,
      params: params,
      return_type: nil,
      fallible: true,
      rc_required: true,
      blocks: [],
      entry_block: 0,
      locals: %{},
      reg_count: 0,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: kind,
      fusion_data: entry["fusion_data"]
    }

    {{module, name}, plan}
  end

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
