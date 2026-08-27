defmodule Elmc.Backend.Plan.Fusion.Registry do
  @moduledoc """
  Registry for generic whole-function C fusion emitters.

  IR matchers live under `Elmc.Backend.Plan.Fusion.Matchers.*`; this module owns provider
  ordering and runtime metadata caches for plan-primary fusion.
  """

  alias ElmEx.IR.PipeChain

  alias Elmc.Backend.CCodegen.Types, as: CCodegenTypes

  alias Elmc.Backend.Plan.Fusion.Matchers.{
    FilterMapRowDrop,
    FoldlOffsetPatch,
    FusionSupport,
    ListConcatReversedRowSlices,
    ListMapStaticIndexAt,
    PermuteMergeInversePipeline,
    ReverseFoldlOccupied,
    RowSliceAdjacentMerge,
    SpawnTileChain,
    TailRecursiveLoop,
    Tuple2CaseTable,
    UnionCaseFourPerm,
    UnionStringCase,
    UnionIntCase,
    UnionIntSuffixCase,
    MaybeIntStringCase,
    IntStringCase,
    MaybeWithDefaultPickSlot
  }

  @runtime_callees_cache_key :elmc_fusion_runtime_callees_cache

  @providers [
    {TailRecursiveLoop, 4},
    {FilterMapRowDrop, 4},
    {FoldlOffsetPatch, 4},
    {UnionCaseFourPerm, 4},
    {ListConcatReversedRowSlices, 4},
    {RowSliceAdjacentMerge, 4},
    {SpawnTileChain, 4},
    {PermuteMergeInversePipeline, 4},
    {ListMapStaticIndexAt, 4},
    {ReverseFoldlOccupied, 4},
    {Tuple2CaseTable, 3},
    {UnionStringCase, 4},
    {UnionIntCase, 4},
    {UnionIntSuffixCase, 4},
    {MaybeIntStringCase, 4},
    {IntStringCase, 4},
    {MaybeWithDefaultPickSlot, 4}
  ]

  @spec providers() :: [{module(), 3 | 4}]
  def providers, do: @providers

  @spec try_emit(String.t(), String.t(), CCodegenTypes.ir_expr() | nil, CCodegenTypes.function_decl_map()) ::
          {:ok, String.t(), [FusionSupport.runtime_callee()]}
          | {:ok, String.t(), [FusionSupport.runtime_callee()], :rc_native}
          | :error
  def try_emit(module_name, name, expr, decl_map) do
    expr = fusion_expr(expr)

    Enum.reduce_while(@providers, :error, fn {mod, arity}, _acc ->
      case apply(mod, :try_emit, apply_args(arity, module_name, name, expr, decl_map)) do
        {:ok, code, callees, :rc_native} -> {:halt, {:ok, code, callees, :rc_native}}
        {:ok, code, callees} -> {:halt, {:ok, code, callees}}
        {:ok, code} -> {:halt, {:ok, code, []}}
        :error -> {:cont, :error}
      end
    end)
  end

  @type compact_list_field_key :: {String.t(), String.t(), String.t()}

  @spec reset_caches!() :: :ok
  def reset_caches! do
    Process.put(@runtime_callees_cache_key, %{})
    Process.put(:elmc_rc_native_fusion_arg_kinds, %{})
    Process.put(:elmc_fusion_rc_native_only, MapSet.new())
    Process.put(:elmc_union_int_fusion_luts, %{})
    :ok
  end

  @spec compact_list_field_keys(String.t(), String.t(), CCodegenTypes.ir_expr() | nil, CCodegenTypes.function_decl_map()) ::
          [compact_list_field_key()]
  def compact_list_field_keys(module_name, name, expr, decl_map) do
    expr = fusion_expr(expr)
    PermuteMergeInversePipeline.compact_list_field_keys(module_name, name, expr, decl_map)
  end

  @spec register_rc_native_arg_kinds(String.t(), String.t(), [atom()]) :: :ok
  def register_rc_native_arg_kinds(module, name, kinds) when is_list(kinds) do
    cache = Process.get(:elmc_rc_native_fusion_arg_kinds, %{})
    Process.put(:elmc_rc_native_fusion_arg_kinds, Map.put(cache, {module, name}, kinds))
    :ok
  end

  @spec clear_rc_native_arg_kinds(String.t(), String.t()) :: :ok
  def clear_rc_native_arg_kinds(module, name) when is_binary(module) and is_binary(name) do
    cache = Process.get(:elmc_rc_native_fusion_arg_kinds, %{})
    Process.put(:elmc_rc_native_fusion_arg_kinds, Map.delete(cache, {module, name}))

    set = Process.get(:elmc_fusion_rc_native_only, MapSet.new())
    Process.put(:elmc_fusion_rc_native_only, MapSet.delete(set, {module, name}))
    :ok
  end

  @spec register_rc_native_only(String.t(), String.t()) :: :ok
  def register_rc_native_only(module, name) when is_binary(module) and is_binary(name) do
    set = Process.get(:elmc_fusion_rc_native_only, MapSet.new())
    Process.put(:elmc_fusion_rc_native_only, MapSet.put(set, {module, name}))
    :ok
  end

  @spec rc_native_only?({String.t(), String.t()}) :: boolean()
  def rc_native_only?({module, name}) do
    MapSet.member?(Process.get(:elmc_fusion_rc_native_only, MapSet.new()), {module, name})
  end

  @spec rc_native_fusion_arg_kinds({String.t(), String.t()}) :: [atom()] | nil
  def rc_native_fusion_arg_kinds({module, name}) do
    Process.get(:elmc_rc_native_fusion_arg_kinds, %{}) |> Map.get({module, name})
  end

  @spec register_union_int_lut(String.t(), String.t(), %{optional(integer()) => integer()}) :: :ok
  def register_union_int_lut(module, name, lut) when is_map(lut) do
    cache = Process.get(:elmc_union_int_fusion_luts, %{})
    Process.put(:elmc_union_int_fusion_luts, Map.put(cache, {module, name}, lut))
    :ok
  end

  @spec union_int_lut_lookup({String.t(), String.t()}, integer()) :: {:ok, integer()} | :error
  def union_int_lut_lookup({module, name}, union_tag) when is_integer(union_tag) do
    case Process.get(:elmc_union_int_fusion_luts, %{}) |> Map.get({module, name}) do
      %{^union_tag => wire} when is_integer(wire) -> {:ok, wire}
      _ -> :error
    end
  end

  @spec infer_native_tag_fusion_arg_kinds(String.t(), CCodegenTypes.function_decl()) :: [atom()] | nil
  def infer_native_tag_fusion_arg_kinds(c_body, decl) when is_binary(c_body) do
    args = Map.get(decl, :args, [])
    arg_count = length(args)

    cond do
      arg_count > 0 and native_boxed_union_param_fusion?(c_body, args) ->
        List.duplicate(:boxed, arg_count)

      String.contains?(c_body, "case_msg_tag_") or String.contains?(c_body, "elmc_int_t case_tag") ->
        args
        |> Enum.with_index()
        |> Enum.map(fn
          {_, 0} -> :boxed_int_tag
          _ -> :boxed
        end)

      # Prefer parsing the real `_native(ElmcValue **out, …)` param list so mixed
      # Int/boxed helpers (e.g. TailRecursiveLoop) are not collapsed to all-native.
      arg_count > 0 and match?({:ok, _}, parse_rc_native_out_param_kinds(c_body, arg_count)) ->
        {:ok, kinds} = parse_rc_native_out_param_kinds(c_body, arg_count)
        kinds

      arg_count > 0 and native_seed_fusion?(c_body) ->
        List.duplicate(:native_int, arg_count)

      true ->
        nil
    end
  end

  defp native_boxed_union_param_fusion?(c_body, [param | _]) when is_binary(param) do
    String.contains?(c_body, "_native(ElmcValue **out, ElmcValue *#{param}")
  end

  defp native_boxed_union_param_fusion?(_, _), do: false

  defp native_seed_fusion?(c_body) do
    String.match?(c_body, ~r/_native\(ElmcValue \*\*out, const elmc_int_t /) or
      String.match?(c_body, ~r/_native\(ElmcValue \*\*out, elmc_int_t /)
  end

  defp parse_rc_native_out_param_kinds(c_body, arg_count)
       when is_binary(c_body) and is_integer(arg_count) and arg_count > 0 do
    case Regex.run(~r/_native\s*\(\s*ElmcValue\s*\*\*\s*\w+\s*,([^)]*)\)/, c_body) do
      [_, params] ->
        kinds =
          params
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(fn
            "const elmc_int_t " <> _ -> :native_int
            "elmc_int_t " <> _ -> :native_int
            "const bool " <> _ -> :native_bool
            "bool " <> _ -> :native_bool
            "ElmcValue *" <> _ -> :boxed
            "ElmcValue* " <> _ -> :boxed
            _ -> :boxed
          end)

        if length(kinds) == arg_count, do: {:ok, kinds}, else: :error

      _ ->
        :error
    end
  end

  @spec runtime_callees(String.t(), String.t(), CCodegenTypes.ir_expr() | nil, CCodegenTypes.function_decl_map()) ::
          [FusionSupport.callee_key()] | nil
  def runtime_callees(module_name, name, _expr, decl_map) do
    key = {module_name, name}
    cache = Process.get(@runtime_callees_cache_key, %{})

    case Map.fetch(cache, key) do
      {:ok, callees} ->
        callees

      :error ->
        expr =
          case Map.get(decl_map, key) do
            %{expr: decl_expr} -> decl_expr
            _ -> nil
          end

        callees = compute_runtime_callees(module_name, name, expr, decl_map)
        Process.put(@runtime_callees_cache_key, Map.put(cache, key, callees))
        callees
    end
  end

  defp compute_runtime_callees(module_name, name, expr, decl_map) do
    case try_emit(module_name, name, fusion_expr(expr), decl_map) do
      {:ok, _, callees, :rc_native} -> callees
      {:ok, _, callees} -> callees
      :error -> nil
    end
  end

  defp apply_args(3, module_name, name, expr, _decl_map), do: [module_name, name, expr]
  defp apply_args(4, module_name, name, expr, decl_map), do: [module_name, name, expr, decl_map]

  defp fusion_expr(%{op: :pipe_chain} = expr), do: PipeChain.desugar(expr)
  defp fusion_expr(expr), do: expr

  @spec rc_native_fusion?(String.t(), String.t(), CCodegenTypes.ir_expr() | nil, CCodegenTypes.function_decl_map()) ::
          boolean()
  def rc_native_fusion?(module_name, name, expr, decl_map) do
    match?({:ok, _, _, :rc_native}, try_emit(module_name, name, expr, decl_map))
  end
end
