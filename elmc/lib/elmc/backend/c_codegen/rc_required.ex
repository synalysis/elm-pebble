defmodule Elmc.Backend.CCodegen.RcRequired do
  @moduledoc false

  alias Elmc.Backend.CCodegen.GenericReachability
  alias Elmc.Backend.CCodegen.Native.FunctionCall, as: NativeFunctionCall
  alias Elmc.Backend.CCodegen.Types
  @worker_entry_points ~w(init update subscriptions)

  # Pebble scene glue calls `view` with the RC ABI when not using direct-render-only.
  @platform_view_entry ~w(view)

  @platform_worker_rc_abi @worker_entry_points ++ @platform_view_entry

  @non_allocating_qualified MapSet.new([
    "List.length",
    "Elm.Kernel.List.length",
    "List.isEmpty",
    "Elm.Kernel.List.isEmpty",
    "String.length",
    "String.isEmpty",
    "Basics.not"
  ])

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
    "elmc_string_concat_parts",
    "elmc_string_from_int",
    "elmc_string_from_native_int",
    "elmc_cmd0",
    "elmc_cmd1",
    "elmc_cmd1_string",
    "elmc_cmd2",
    "elmc_cmd3",
    "elmc_cmd4",
    "elmc_cmd5",
    "elmc_basics_compare",
    "elmc_cmd_queue_append",
    "elmc_render_cmd6",
    "elmc_apply_extra",
    "elmc_forward_ref_capture"
  ])

  @type run_opts :: keyword() | Elmc.Types.compile_options()

  @spec run!(Types.function_decl_map(), run_opts()) :: MapSet.t(Types.function_decl_key())
  def run!(decl_map, opts \\ []) do
    set = analyze(decl_map, opts)
    Process.put(:elmc_rc_required, set)
    set
  end

  @spec analyze(Types.function_decl_map(), run_opts()) :: MapSet.t(Types.function_decl_key())
  def analyze(decl_map, opts \\ []) do
    seeds = initial_seeds(decl_map, opts)

    decl_map
    |> then(&expand_rc_required(seeds, &1))
    |> expand_native_boxed_rc_callers(decl_map)
    |> expand_scalar_boxing_wrappers(decl_map)
  end

  defp expand_rc_required(required, decl_map) do
    expanded =
      Enum.reduce(decl_map, required, fn {key, decl}, acc ->
        if is_map(decl) and body_allocates?(decl.expr) do
          MapSet.put(acc, key)
        else
          acc
        end
      end)
      |> then(&callee_closure(&1, decl_map))

    if MapSet.equal?(expanded, required) do
      expanded
    else
      expand_rc_required(expanded, decl_map)
    end
  end

  defp initial_seeds(decl_map, opts) do
    worker_seeds =
      decl_map
      |> Map.keys()
      |> Enum.filter(fn {_module, name} -> name in seed_entry_names(opts) end)
      |> MapSet.new()

    MapSet.union(worker_seeds, direct_command_target_seeds(opts))
  end

  # Direct-render scene helpers (for example drawDial) are not always reachable from
  # init/update/subscriptions, but their allocating callees must use the RC ABI.
  defp direct_command_target_seeds(opts) do
    if direct_render_only?(opts) do
      direct_command_targets_from_opts(opts)
    else
      MapSet.new()
    end
  end

  defp direct_command_targets_from_opts(opts) when is_list(opts),
    do: Keyword.get(opts, :direct_command_targets, MapSet.new())

  defp direct_command_targets_from_opts(%{} = opts),
    do: Map.get(opts, :direct_command_targets, MapSet.new())

  # Int/Bool native helpers still box through elmc_new_int/bool in their argc wrapper;
  # that allocation can fail and must propagate RC to callers/runtime logging.
  defp expand_scalar_boxing_wrappers(required, decl_map) do
    Enum.reduce(decl_map, required, fn {key = {mod, _name}, decl}, acc ->
      if MapSet.member?(acc, key) or not scalar_boxing_rc_required?(decl, mod, decl_map) do
        acc
      else
        MapSet.put(acc, key)
      end
    end)
  end

  defp scalar_boxing_rc_required?(decl, module_name, decl_map) do
    NativeFunctionCall.native_scalar_fn?(decl, module_name, decl_map) and
      NativeFunctionCall.return_kind(decl, module_name, decl_map) in [:native_int, :native_bool]
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

  @spec worker_entry_point?(String.t()) :: boolean()
  def worker_entry_point?(name) when is_binary(name), do: name in @worker_entry_points
  def worker_entry_point?(_), do: false

  @doc false
  @spec platform_worker_rc_abi?(String.t(), String.t(), Types.function_decl_map() | nil) ::
          boolean()
  def platform_worker_rc_abi?(module_name, name, decl_map \\ nil)

  def platform_worker_rc_abi?(module_name, name, nil) do
    platform_worker_rc_abi?(module_name, name, Process.get(:elmc_program_decls, %{}))
  end

  def platform_worker_rc_abi?(module_name, name, decl_map) when is_map(decl_map) do
    name in @platform_worker_rc_abi and Map.has_key?(decl_map, {module_name, name})
  end

  @spec worker_callback?(String.t()) :: boolean()
  def worker_callback?(name), do: worker_entry_point?(name)

  @spec lambda_body_rc_required?(term(), String.t(), Types.function_decl_map()) :: boolean()
  def lambda_body_rc_required?(expr, module_name, decl_map) do
    required = Process.get(:elmc_rc_required, MapSet.new())

    expr_allocates?(expr) or calls_required?(expr, module_name, decl_map, required)
  end

  defp seed_entry_names(opts) do
    if direct_render_only?(opts) do
      @worker_entry_points
    else
      @worker_entry_points ++ @platform_view_entry
    end
  end

  defp direct_render_only?(opts) when is_list(opts), do: opts[:direct_render_only] == true

  defp direct_render_only?(%{} = opts),
    do: Map.get(opts, :direct_render_only) == true or Map.get(opts, "direct_render_only") == true

  defp direct_render_only?(_), do: false

  defp native_scalar_callee?({mod, name}, decl_map) do
    case Map.fetch(decl_map, {mod, name}) do
      {:ok, decl} -> NativeFunctionCall.native_scalar_fn?(decl, mod, decl_map)
      :error -> false
    end
  end

  @spec body_allocates?(Types.ir_expr() | nil) :: boolean()
  def body_allocates?(expr), do: expr_allocates?(expr || %{op: :int_literal, value: 0})

  defp callee_closure(required, decl_map) do
    expanded =
      Enum.reduce(required, required, fn {mod, name}, acc ->
        decl = Map.fetch!(decl_map, {mod, name})

        decl.expr
        |> GenericReachability.expr_callees(mod, decl_map)
        |> Enum.reduce(acc, fn callee, acc2 ->
          if native_scalar_callee?(callee, decl_map) do
            acc2
          else
            MapSet.put(acc2, callee)
          end
        end)
      end)

    if MapSet.equal?(expanded, required) do
      expanded
    else
      callee_closure(expanded, decl_map)
    end
  end

  # List.map and other higher-order call sites do not always surface direct callee
  # edges, but any function that calls a native boxed RC helper must itself use the
  # RC ABI so failures propagate through CHECK_RC instead of being swallowed.
  defp expand_native_boxed_rc_callers(required, decl_map) do
    expanded =
      Enum.reduce(decl_map, required, fn {key = {mod, _name}, decl}, acc ->
        cond do
          MapSet.member?(acc, key) or not is_map(decl.expr) ->
            acc

          not calls_native_boxed_rc_callee?(decl.expr, mod, decl_map) ->
            acc

          callee_of_required?(key, acc, decl_map) ->
            MapSet.put(acc, key)

          true ->
            acc
        end
      end)

    if MapSet.equal?(expanded, required) do
      expanded
    else
      expand_native_boxed_rc_callers(expanded, decl_map)
    end
  end

  defp callee_of_required?(callee_key, required, decl_map) do
    Enum.any?(required, fn caller_key ->
      case Map.fetch(decl_map, caller_key) do
        {:ok, caller_decl} ->
          caller_decl.expr
          |> GenericReachability.expr_callees(elem(caller_key, 0), decl_map)
          |> Enum.member?(callee_key)

        :error ->
          false
      end
    end)
  end

  defp calls_native_boxed_rc_callee?(expr, module_name, decl_map) do
    expr
    |> GenericReachability.expr_callees(module_name, decl_map)
    |> Enum.any?(fn {mod, _name} = key ->
      case Map.fetch(decl_map, key) do
        {:ok, decl} -> NativeFunctionCall.native_boxed_rc_candidate?(decl, mod, decl_map)
        :error -> false
      end
    end)
  end

  defp calls_required?(expr, module_name, decl_map, required) do
    expr
    |> GenericReachability.expr_callees(module_name, decl_map)
    |> Enum.any?(&MapSet.member?(required, &1))
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

  defp allocating_runtime_calls(%{op: :qualified_call, target: target, args: args}) do
    own = if allocating_qualified_target?(target), do: ["qualified_call:#{target}"], else: []
    own ++ Enum.flat_map(args || [], &allocating_runtime_calls/1)
  end

  defp allocating_runtime_calls(%{op: :call, name: "__append__", args: args}) do
    ["list_append" | Enum.flat_map(args || [], &allocating_runtime_calls/1)]
  end

  defp allocating_runtime_calls(%{op: :record_literal, fields: fields}) when is_list(fields) do
    ["record_literal" |
     Enum.flat_map(fields, fn
       %{expr: expr} -> allocating_runtime_calls(expr)
       {_, value} -> allocating_runtime_calls(value)
       value -> allocating_runtime_calls(value)
     end)]
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
      String.starts_with?(function, "elmc_cmd") or
      String.starts_with?(function, "elmc_render_cmd")
  end

  defp allocating_function?(_), do: false

  defp allocating_qualified_target?(target) when is_binary(target) do
    not MapSet.member?(@non_allocating_qualified, target) and
      allocating_qualified_module?(target)
  end

  defp allocating_qualified_module?(<<"List.", _::binary>>), do: true
  defp allocating_qualified_module?(<<"String.", _::binary>>), do: true
  defp allocating_qualified_module?(<<"Dict.", _::binary>>), do: true
  defp allocating_qualified_module?(<<"Set.", _::binary>>), do: true
  defp allocating_qualified_module?(<<"Maybe.", _::binary>>), do: true
  defp allocating_qualified_module?(<<"Result.", _::binary>>), do: true
  defp allocating_qualified_module?(<<"Tuple.", _::binary>>), do: true
  defp allocating_qualified_module?(<<"Json.Decode.", _::binary>>), do: true
  defp allocating_qualified_module?(<<"Json.Encode.", _::binary>>), do: true
  defp allocating_qualified_module?(_), do: false
end
