defmodule Elmc.Backend.CCodegen.Fusion do
  @moduledoc """
  Registry for generic whole-function C emitters.

  Providers must match reusable IR shapes and emit C that preserves the Elm
  semantics for every function with that shape. A provider implements
  `try_emit/3` or `try_emit/4` and returns `{:ok, c_source}` or
  `{:ok, c_source, runtime_callees}`; unmatched IR returns `:error`.
  """

  alias Elmc.Backend.CCodegen.{
    FilterMapRowDrop,
    FoldlOffsetPatch,
    FusionSupport,
    ListConcatReversedRowSlices,
    ListMapStaticIndexAt,
    PermuteMergeInversePipeline,
    ReverseFoldlOccupied,
    RowSliceAdjacentMerge,
    Tuple2CaseTable,
    UnionCaseFourPerm
  }

  @providers [
    {FilterMapRowDrop, 4},
    {FoldlOffsetPatch, 4},
    {UnionCaseFourPerm, 4},
    {ListConcatReversedRowSlices, 4},
    {RowSliceAdjacentMerge, 4},
    {PermuteMergeInversePipeline, 4},
    {ListMapStaticIndexAt, 4},
    {ReverseFoldlOccupied, 4},
    {Tuple2CaseTable, 3}
  ]

  @spec try_emit(String.t(), String.t(), map() | nil, map()) ::
          {:ok, String.t(), [FusionSupport.callee_key()]} | {:ok, String.t(), [FusionSupport.callee_key()], :rc_native} | :error
  def try_emit(module_name, name, expr, decl_map) do
    Enum.find_value(@providers, :error, fn {mod, arity} ->
      case apply(mod, :try_emit, apply_args(arity, module_name, name, expr, decl_map)) do
        {:ok, code, callees, :rc_native} -> {:ok, code, callees, :rc_native}
        {:ok, code, callees} -> {:ok, code, callees}
        {:ok, code} -> {:ok, code, []}
        :error -> nil
      end
    end)
  end

  @spec runtime_callees(String.t(), String.t(), map() | nil, map()) ::
          [FusionSupport.callee_key()] | nil
  def runtime_callees(module_name, name, expr, decl_map) do
    case try_emit(module_name, name, expr, decl_map) do
      {:ok, _, callees, :rc_native} -> callees
      {:ok, _, callees} -> callees
      :error -> nil
    end
  end

  defp apply_args(3, module_name, name, expr, _decl_map), do: [module_name, name, expr]
  defp apply_args(4, module_name, name, expr, decl_map), do: [module_name, name, expr, decl_map]
end
