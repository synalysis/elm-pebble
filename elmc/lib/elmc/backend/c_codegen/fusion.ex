defmodule Elmc.Backend.CCodegen.Fusion do
  @moduledoc """
  Registry for generic whole-function C emitters.

  Providers must match reusable IR shapes and emit C that preserves the Elm
  semantics for every function with that shape. A provider implements
  `try_emit/3` or `try_emit/4` and returns `{:ok, c_source}` or
  `{:ok, c_source, runtime_callees}`; unmatched IR returns `:error`.
  """

  alias ElmEx.IR.PipeChain

  alias Elmc.Backend.CCodegen.{
    FilterMapRowDrop,
    FoldlOffsetPatch,
    FusionSupport,
    ListConcatReversedRowSlices,
    ListMapStaticIndexAt,
    PermuteMergeInversePipeline,
    ReverseFoldlOccupied,
    RowSliceAdjacentMerge,
    SpawnTileChain,
    Tuple2CaseTable,
    UnionCaseFourPerm,
    UnionStringCase,
    UnionIntCase,
    UnionIntSuffixCase,
    MaybeIntStringCase,
    IntStringCase
  }

  @runtime_callees_cache_key :elmc_fusion_runtime_callees_cache

  @providers [
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
    {IntStringCase, 4}
  ]

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]} | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(module_name, name, expr, decl_map) do
    expr = fusion_expr(expr)

    Enum.find_value(@providers, :error, fn {mod, arity} ->
      case apply(mod, :try_emit, apply_args(arity, module_name, name, expr, decl_map)) do
        {:ok, code, callees, :rc_native} -> {:ok, code, callees, :rc_native}
        {:ok, code, callees} -> {:ok, code, callees}
        {:ok, code} -> {:ok, code, []}
        :error -> nil
      end
    end)
  end

  @type compact_list_field_key :: {String.t(), String.t(), String.t()}

  @spec reset_caches!() :: :ok
  def reset_caches! do
    Process.put(@runtime_callees_cache_key, %{})
    Process.put(:elmc_rc_native_fusion_arg_kinds, %{})
    Process.put(:elmc_union_int_fusion_luts, %{})
    :ok
  end

  @spec compact_list_field_keys(String.t(), String.t(), map() | nil, map()) ::
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

  @spec infer_native_tag_fusion_arg_kinds(String.t(), map()) :: [atom()] | nil
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

  @spec runtime_callees(String.t(), String.t(), map() | nil, map()) ::
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

  @spec rc_native_fusion?(String.t(), String.t(), map() | nil, map()) :: boolean()
  def rc_native_fusion?(module_name, name, expr, decl_map) do
    match?({:ok, _, _, :rc_native}, try_emit(module_name, name, expr, decl_map))
  end
end
