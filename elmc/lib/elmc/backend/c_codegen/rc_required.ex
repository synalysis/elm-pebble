defmodule Elmc.Backend.CCodegen.RcRequired do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Fusion
  alias Elmc.Backend.CCodegen.GenericReachability
  alias Elmc.Backend.CCodegen.ImmortalStaticList
  alias Elmc.Backend.CCodegen.Types

  @worker_callbacks ~w(init update subscriptions view)

  @allocating_runtime_calls MapSet.new([
    "elmc_new_int",
    "elmc_new_bool",
    "elmc_new_float",
    "elmc_new_string",
    "elmc_list_cons",
    "elmc_list_from_values",
    "elmc_list_from_values_take",
    "elmc_record_new",
    "elmc_record_new_take",
    "elmc_record_new_values_ints",
    "elmc_record_new_values_take",
    "elmc_record_set",
    "elmc_record_set_index",
    "elmc_tuple2",
    "elmc_tuple2_take",
    "elmc_maybe",
    "elmc_result",
    "elmc_closure_new",
    "elmc_string_append",
    "elmc_string_from_int",
    "elmc_string_from_native_int",
    "elmc_cmd1",
    "elmc_cmd2",
    "elmc_cmd3",
    "elmc_cmd4",
    "elmc_cmd_queue_append",
    "elmc_apply_extra",
    "elmc_forward_ref_capture",
    "elmc_retain"
  ])

  @spec run!(Types.function_decl_map(), keyword()) :: MapSet.t(Types.function_decl_key())
  def run!(decl_map, opts \\ []) do
    set = analyze(decl_map, opts)
    Process.put(:elmc_rc_required, set)
    set
  end

  @spec analyze(Types.function_decl_map(), keyword()) :: MapSet.t(Types.function_decl_key())
  def analyze(decl_map, _opts \\ []) do
    seeds =
      decl_map
      |> Map.keys()
      |> Enum.filter(fn {_module, name} -> worker_callback?(name) end)
      |> MapSet.new()

    fixed_point(seeds, decl_map)
  end

  @spec rc_required?(String.t(), String.t()) :: boolean()
  def rc_required?(module_name, name) do
    rc_required?({module_name, name})
  end

  @spec rc_required?(Types.function_decl_key()) :: boolean()
  def rc_required?({module_name, name}) do
    Process.get(:elmc_rc_required, MapSet.new())
    |> MapSet.member?({module_name, name})
  end

  @spec worker_callback?(String.t()) :: boolean()
  def worker_callback?(name) when is_binary(name), do: name in @worker_callbacks
  def worker_callback?(_), do: false

  @spec lambda_body_rc_required?(term(), String.t(), Types.function_decl_map()) :: boolean()
  def lambda_body_rc_required?(expr, module_name, decl_map) do
    required = Process.get(:elmc_rc_required, MapSet.new())

    expr_allocates?(expr) or calls_required?(expr, module_name, decl_map, required)
  end

  defp fixed_point(required, decl_map) do
    expanded =
      decl_map
      |> Map.keys()
      |> Enum.filter(fn key ->
        MapSet.member?(required, key) or body_needs_rc?(key, Map.fetch!(decl_map, key), decl_map, required)
      end)
      |> MapSet.new()

    if MapSet.equal?(expanded, required) do
      expanded
    else
      fixed_point(expanded, decl_map)
    end
  end

  defp body_needs_rc?({module, name}, decl, decl_map, required) do
    worker_callback?(name) or
      (not immortal_static_list_body?(module, name, decl) and
         (fusion_allocates?(module, name, decl.expr, decl_map) or
            expr_allocates?(decl.expr) or
            calls_required?(decl.expr, module, decl_map, required)))
  end

  defp immortal_static_list_body?(module, name, decl) do
    ImmortalStaticList.zero_arg_function?(decl) and
      match?(
        {:ok, _, _},
        ImmortalStaticList.try_emit_function_prelude_and_body(
          module,
          name,
          decl.expr || %{op: :int_literal, value: 0},
          false
        )
      )
  end

  defp calls_required?(expr, module_name, decl_map, required) do
    expr
    |> GenericReachability.expr_callees(module_name, decl_map)
    |> Enum.any?(&MapSet.member?(required, &1))
  end

  defp fusion_allocates?(module_name, name, expr, decl_map) do
    case Fusion.try_emit(module_name, name, expr, decl_map) do
      {:ok, _, _} -> true
      :error -> false
    end
  end

  defp expr_allocates?(expr) do
    expr
    |> allocating_runtime_calls()
    |> Enum.any?()
  end

  defp allocating_runtime_calls(nil), do: []

  defp allocating_runtime_calls(%{op: :list_literal, items: items}) when is_list(items) and items != [] do
    ["list_literal" | Enum.flat_map(items, &allocating_runtime_calls/1)]
  end

  defp allocating_runtime_calls(%{op: :runtime_call, function: function} = expr) do
    own =
      if MapSet.member?(@allocating_runtime_calls, function) or allocating_function?(function),
        do: [function],
        else: []

    own ++ Enum.flat_map(Map.values(expr), &allocating_runtime_calls/1)
  end

  defp allocating_runtime_calls(%{op: :constructor_call} = expr) do
    ["constructor_call" | Enum.flat_map(Map.values(expr), &allocating_runtime_calls/1)]
  end

  defp allocating_runtime_calls(expr) when is_map(expr) do
    expr |> Map.values() |> Enum.flat_map(&allocating_runtime_calls/1)
  end

  defp allocating_runtime_calls(values) when is_list(values) do
    Enum.flat_map(values, &allocating_runtime_calls/1)
  end

  defp allocating_runtime_calls(_), do: []

  defp allocating_function?(function) when is_binary(function) do
    String.starts_with?(function, "elmc_new_") or
      String.starts_with?(function, "elmc_record_new") or
      String.starts_with?(function, "elmc_list_") or
      String.starts_with?(function, "elmc_tuple") or
      String.starts_with?(function, "elmc_maybe") or
      String.starts_with?(function, "elmc_result") or
      String.starts_with?(function, "elmc_closure") or
      String.starts_with?(function, "elmc_string") or
      String.starts_with?(function, "elmc_dict") or
      String.starts_with?(function, "elmc_set") or
      String.starts_with?(function, "elmc_cmd")
  end

  defp allocating_function?(_), do: false
end
