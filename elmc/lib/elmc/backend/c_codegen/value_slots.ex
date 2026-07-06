defmodule Elmc.Backend.CCodegen.ValueSlots do
  @moduledoc false

  alias Elmc.Backend.CCodegen.OwnershipTransfer
  alias Elmc.Backend.CCodegen.RcRuntimeEmit

  @owned_ref ~r/^owned\[(\d+)\]$/
  @heap_owned_slot_threshold 24

  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) do
    epilogue_lifo? = Keyword.get(opts, :epilogue_lifo, false)

    Process.put(:elmc_value_slots, %{
      next: 0,
      live: MapSet.new(),
      transferred: MapSet.new(),
      tuple_projections: %{},
      written: MapSet.new(),
      loop_depth: 0,
      epilogue_lifo: epilogue_lifo?,
      heap_owned_count: 0,
      result_slot_root: nil,
      result_slot_current: nil,
      function_out_written: false,
      deferred_nulls: [],
      direct_param_owned: %{},
      emit_owned_epilogue: epilogue_lifo?
    })

    Process.delete(:elmc_result_slot_root)
    Process.delete(:elmc_result_slot_current)

    :ok
  end

  @spec epilogue_lifo?() :: boolean()
  def epilogue_lifo? do
    Map.get(slots_state(), :epilogue_lifo, false)
  end

  @doc """
  Track the first owned slot that retains a direct-render parameter.

  When the same parameter is retained into multiple owned slots, alias later slots
  to the first instead of introducing duplicate pointer entries.
  """
  @spec track_direct_param_owned(String.t(), String.t()) :: :ok
  def track_direct_param_owned(source, owned_var)
      when is_binary(source) and is_binary(owned_var) do
    slots = slots_state()

    Process.put(:elmc_value_slots, %{
      slots
      | direct_param_owned: Map.put(slots.direct_param_owned, source, owned_var)
    })

    :ok
  end

  @spec direct_param_owned_slot(String.t()) :: String.t() | nil
  def direct_param_owned_slot(source) when is_binary(source) do
    Map.get(slots_state().direct_param_owned, source)
  end

  @type snapshot :: %{
          transferred: MapSet.t(),
          tuple_projections: map(),
          live: MapSet.t(),
          written: MapSet.t(),
          direct_param_owned: map()
        }

  @doc "Capture transfer/projection marks before a divergent branch (not slot indices)."
  @spec snapshot() :: snapshot()
  def snapshot do
    slots = slots_state()

    %{
      transferred: slots.transferred,
      tuple_projections: slots.tuple_projections,
      live: slots.live,
      written: slots.written,
      direct_param_owned: slots.direct_param_owned
    }
  end

  @doc "Restore transfer/projection marks so sibling branches start with a clean slate."
  @spec restore(snapshot()) :: :ok
  def restore(%{
        transferred: transferred,
        tuple_projections: tuple_projections,
        live: live,
        written: written,
        direct_param_owned: direct_param_owned
      }) do
    slots = slots_state()

    Process.put(:elmc_value_slots, %{
      slots
      | transferred: transferred,
        tuple_projections: tuple_projections,
        live: live,
        written: written,
        direct_param_owned: direct_param_owned,
        deferred_nulls: []
    })

    :ok
  end

  @spec alloc() :: {String.t(), non_neg_integer()}
  def alloc do
    slots = slots_state()
    index = slots.next
    live = MapSet.put(slots.live, index)

    Process.put(:elmc_value_slots, %{
      slots
      | next: index + 1,
        live: live
    })

    {ref(index), index}
  end

  @spec ref(non_neg_integer()) :: String.t()
  def ref(index) when is_integer(index) and index >= 0, do: "owned[#{index}]"

  @spec addr(non_neg_integer()) :: String.t()
  def addr(index) when is_integer(index) and index >= 0, do: "&owned[#{index}]"

  @spec owned_ref?(String.t()) :: boolean()
  def owned_ref?(var) when is_binary(var), do: Regex.match?(@owned_ref, var)
  def owned_ref?(_), do: false

  @spec owned_index(String.t()) :: non_neg_integer() | nil
  def owned_index(var) when is_binary(var) do
    case Regex.run(@owned_ref, var) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  @spec track(String.t()) :: :ok
  def track(var) when is_binary(var) do
    case owned_index(var) do
      index when is_integer(index) ->
        slots = slots_state()
        live = MapSet.put(slots.live, index)
        next = max(slots.next, index + 1)
        Process.put(:elmc_value_slots, %{slots | live: live, next: next})

      _ ->
        :ok
    end

    :ok
  end

  @spec transfer(String.t() | non_neg_integer()) :: :ok
  def transfer(var) when is_binary(var) do
    case owned_index(var) do
      nil -> :ok
      index -> transfer(index)
    end
  end

  def transfer(index) when is_integer(index) and index >= 0 do
    slots = slots_state()
    live = MapSet.delete(slots.live, index)
    transferred = MapSet.put(slots.transferred, index)
    Process.put(:elmc_value_slots, %{slots | live: live, transferred: transferred})
    :ok
  end

  @type tuple_projection :: :first | :second

  @doc """
  After `elmc_tuple2_take(dest, left, right)`, operands moved into `dest` are
  nulled in their owned slots. Register where each operand lives so a later
  retain of the old slot reads through `elmc_tuple_first` / `elmc_tuple_second`.
  """
  @spec register_tuple_projection(String.t(), String.t(), tuple_projection()) :: :ok
  def register_tuple_projection(operand_ref, dest_ref, which)
      when which in [:first, :second] and is_binary(operand_ref) and is_binary(dest_ref) do
    with src when is_integer(src) <- owned_index(operand_ref),
         dest when is_integer(dest) <- owned_index(dest_ref) do
      slots = slots_state()
      projections = Map.put(slots.tuple_projections, src, {dest, which})
      Process.put(:elmc_value_slots, %{slots | tuple_projections: projections})
    end

    :ok
  end

  @spec tuple_projection_retain_c_expr(String.t()) :: String.t() | nil
  def tuple_projection_retain_c_expr(source) when is_binary(source) do
    case owned_index(source) do
      nil ->
        nil

      src ->
        case Map.get(slots_state().tuple_projections, src) do
          {dest, which} ->
            if not MapSet.member?(slots_state().transferred, dest) do
              case which do
                :first -> "elmc_retain(elmc_tuple_first(#{ref(dest)}))"
                :second -> "elmc_retain(elmc_tuple_second(#{ref(dest)}))"
              end
            else
              nil
            end

          _ ->
            nil
        end
    end
  end

  @spec release(String.t() | non_neg_integer()) :: :ok
  def release(var) when is_binary(var) do
    case owned_index(var) do
      nil -> :ok
      index -> release(index)
    end
  end

  def release(index) when is_integer(index) and index >= 0 do
    slots = slots_state()
    Process.put(:elmc_value_slots, %{slots | live: MapSet.delete(slots.live, index)})
    :ok
  end

  @doc """
  Emit a release for `var`. Owned slots are released and nulled so epilogue
  lifo does not double-free. Use `abandon_stmt/1` only after ownership transfer.
  """
  @spec abandon_stmt(String.t()) :: String.t()
  def abandon_stmt(var) when is_binary(var) do
    if owned_ref?(var) do
      release(var)
      null_assignment(var)
    else
      ""
    end
  end

  @spec release_stmt(String.t()) :: String.t()
  def release_stmt(var) when is_binary(var) do
    cond do
      RcRuntimeEmit.function_out_ref?(var) ->
        ""

      owned_ref?(var) ->
        release_owned_and_null(var)

      true ->
        "elmc_release(#{RcRuntimeEmit.value_expr(var)});"
    end
  end

  @doc "Like `release_stmt/1`, but omits a line when there is nothing to emit."
  @spec release_stmt_line(String.t()) :: String.t()
  def release_stmt_line(var) when is_binary(var) do
    case release_stmt(var) do
      "" ->
        ""

      stmt ->
        cond do
          String.contains?(stmt, "\n") -> stmt
          String.ends_with?(stmt, ";") -> stmt
          true -> stmt <> ";"
        end
    end
  end

  @spec null_assignment(String.t() | non_neg_integer()) :: String.t()
  def null_assignment(var) when is_binary(var) do
    "#{RcRuntimeEmit.assignment_lhs(var)} = NULL;"
  end

  def null_assignment(index) when is_integer(index), do: null_assignment(ref(index))

  @spec boxed_decl(String.t(), String.t(), map()) :: String.t()
  def boxed_decl(var, rhs, env \\ %{}) when is_binary(var) and is_binary(rhs) do
    case RcRuntimeEmit.parse_allocator_call(rhs) do
      {:ok, alloc_fn, call_args} ->
        RcRuntimeEmit.fusion_assign(var, alloc_fn, call_args, env)

      :error ->
        cond do
          RcRuntimeEmit.function_out_ref?(var) ->
            RcRuntimeEmit.assign_stmt(var, rhs)

          owned_ref?(var) ->
            var = ensure_fresh_assign_target(var)
            stmt = owned_reassign_prefix(var) <> "#{var} = #{RcRuntimeEmit.value_expr(rhs)};"
            mark_written(var)
            stmt

          true ->
            "ElmcValue *#{var} = #{RcRuntimeEmit.value_expr(rhs)};"
        end
    end
  end

  @spec boxed_null_decl(String.t()) :: String.t()
  def boxed_null_decl(var) when is_binary(var) do
    cond do
      RcRuntimeEmit.function_out_ref?(var) -> RcRuntimeEmit.null_assign_stmt(var)
      owned_ref?(var) -> "#{var} = NULL;"
      true -> "ElmcValue *#{var} = NULL;"
    end
  end

  @doc false
  @spec transferred?(String.t() | non_neg_integer(), String.t() | nil) :: boolean()
  def transferred?(var, body \\ nil)

  def transferred?(var, body) when is_binary(var) do
    case owned_index(var) do
      nil ->
        is_binary(body) and OwnershipTransfer.transferred_in_c_source?(var, body)

      index ->
        transferred?(index, body)
    end
  end

  def transferred?(index, body) when is_integer(index) do
    MapSet.member?(slots_state().transferred, index) or
      (is_binary(body) and OwnershipTransfer.transferred_in_c_source?(ref(index), body))
  end

  @spec slot_count() :: non_neg_integer()
  def slot_count do
    slots_state().next
  end

  @spec owned_declaration() :: String.t()
  def owned_declaration do
    n = slot_count()

    cond do
      n == 0 -> ""
      heap_owned?(n) -> heap_owned_declaration(n)
      true -> "ElmcValue *owned[#{n}] = {0};"
    end
  end

  defp heap_owned?(slot_count) do
    slot_count >= @heap_owned_slot_threshold and pebble_int32_build?() and epilogue_lifo?()
  end

  defp pebble_int32_build? do
    Process.get(:elmc_codegen_opts, %{})[:pebble_int32] == true
  end

  defp heap_owned_declaration(slot_count) do
    slots = slots_state()
    Process.put(:elmc_value_slots, Map.put(slots, :heap_owned_count, slot_count))

    """
    enum { ELMC_OWNED_SLOT_COUNT = #{slot_count} };
    ElmcValue **owned = (ElmcValue **)elmc_malloc(ELMC_OWNED_SLOT_COUNT * sizeof(ElmcValue *), "owned_slots");
    if (!owned) return RC_ERR_OUT_OF_MEMORY;
    for (size_t elmc_owned_i = 0; elmc_owned_i < ELMC_OWNED_SLOT_COUNT; elmc_owned_i++) {
      owned[elmc_owned_i] = NULL;
    }
    """
    |> String.trim()
  end

  defp heap_owned_active? do
    Map.get(slots_state(), :heap_owned_count, 0) > 0
  end

  @spec failure_cleanup() :: String.t()
  def failure_cleanup do
    epilogue_cleanup()
  end

  @doc false
  @spec set_emit_owned_epilogue(boolean()) :: :ok
  def set_emit_owned_epilogue(enabled) when is_boolean(enabled) do
    Process.put(:elmc_value_slots, Map.put(slots_state(), :emit_owned_epilogue, enabled))
    :ok
  end

  @spec epilogue_cleanup() :: String.t()
  def epilogue_cleanup do
    flush =
      if Map.get(slots_state(), :emit_owned_epilogue, false) do
        flush_deferred_nulls()
      else
        Process.put(:elmc_value_slots, Map.put(slots_state(), :deferred_nulls, []))
        ""
      end
    null_borrowed = null_borrowed_field_refs_stmt()

    lifo =
      cond do
        slot_count() == 0 ->
          ""

        heap_owned_active?() ->
          "elmc_release_array_lifo(owned, ELMC_OWNED_SLOT_COUNT);\nelmc_free(owned);"

        true ->
          "elmc_release_array_lifo(owned, DIM(owned));"
      end

    join_stmts([flush, null_borrowed, lifo])
  end

  defp null_borrowed_field_refs_stmt do
    max_slot = slot_count()

    Process.get(:elmc_borrowed_field_refs, MapSet.new())
    |> Enum.filter(fn ref ->
      owned_ref?(ref) and
        case owned_index(ref) do
          index when is_integer(index) -> index < max_slot
          _ -> false
        end
    end)
    |> Enum.map(fn ref -> "#{RcRuntimeEmit.assignment_lhs(ref)} = NULL;" end)
    |> Enum.join("\n")
  end

  @doc """
  After a direct call writes through an owned out-slot, clear owned operands that alias
  the same pointer so epilogue lifo does not release the returned value twice.
  """
  @spec null_call_operands_aliasing_out(String.t(), [String.t()]) :: String.t()
  def null_call_operands_aliasing_out(out, arg_vars)
      when is_binary(out) and is_list(arg_vars) do
    if epilogue_lifo?() and owned_ref?(out) do
      arg_vars
      |> Enum.filter(fn arg -> owned_ref?(arg) and arg != out end)
      |> Enum.map(fn arg ->
        """
        if (#{RcRuntimeEmit.value_expr(out)} == #{RcRuntimeEmit.value_expr(arg)}) {
          #{null_assignment(arg)}
        }
        """
      end)
      |> Enum.join("\n")
      |> case do
        "" -> ""
        code -> code <> "\n"
      end
    else
      ""
    end
  end

  @doc """
  After a self-recursive call, abandon owned argument slots without releasing them.
  The result in `out` retains shared record fields; releasing the arg would drop refs
  still reachable through the result (for example `withPiece` COW on the model param).
  """
  @spec abandon_owned_call_args_after_recursive(String.t(), [String.t()]) :: String.t()
  def abandon_owned_call_args_after_recursive(out, arg_vars)
      when is_binary(out) and is_list(arg_vars) do
    if epilogue_lifo?() do
      arg_vars
      |> Enum.filter(fn arg -> owned_ref?(arg) and arg != out end)
      |> Enum.map(&null_assignment/1)
      |> Enum.join("\n")
      |> case do
        "" -> ""
        code -> code <> "\n"
      end
    else
      ""
    end
  end

  @spec post_call_operand_release(String.t()) :: String.t()
  def post_call_operand_release(var) when is_binary(var) do
    cond do
      RcRuntimeEmit.function_out_ref?(var) -> ""
      owned_ref?(var) and epilogue_lifo?() -> ""
      owned_ref?(var) -> release_owned_and_null(var)
      true -> "elmc_release(#{RcRuntimeEmit.value_expr(var)});"
    end
  end

  @spec release_owned_and_null(String.t()) :: String.t()
  def release_owned_and_null(var) when is_binary(var) do
    cond do
      not epilogue_lifo?() ->
        release_owned_eager(var)

      Map.get(slots_state(), :loop_depth, 0) > 0 ->
        release_owned_eager(var)

      true ->
        ""
    end
  end

  @doc """
  Release an owned slot immediately, even in epilogue-lifo functions.
  Use when the slot will be reassigned before function exit (for example in loops).
  """
  @spec release_owned_eager(String.t()) :: String.t()
  def release_owned_eager(var) when is_binary(var) do
    release(var)
    "ELMC_RELEASE(#{var});\n#{null_assignment(var)}"
  end

  @doc false
  @spec sync_result_slot_current!(String.t()) :: :ok
  def sync_result_slot_current!(out) when is_binary(out) do
    slots = slots_state()
    root = Map.get(slots, :result_slot_root)

    cond do
      is_binary(root) and owned_ref?(out) ->
        Process.put(:elmc_value_slots, Map.put(slots, :result_slot_current, out))

      is_binary(root) and out == root ->
        Process.put(:elmc_value_slots, Map.put(slots, :result_slot_current, root))

      true ->
        :ok
    end

    :ok
  end

  @doc false
  @spec set_result_slot_root(String.t() | nil) :: :ok
  def set_result_slot_root(nil), do: :ok

  def set_result_slot_root(ref) when is_binary(ref) do
    slots = slots_state()
    Process.put(:elmc_value_slots, %{slots | result_slot_root: ref, result_slot_current: ref})
    :ok
  end

  @doc false
  @spec resolve_result_slot(String.t()) :: String.t()
  def resolve_result_slot(var) when is_binary(var) do
    slots = slots_state()

    if var == Map.get(slots, :result_slot_root) do
      Map.get(slots, :result_slot_current, var)
    else
      var
    end
  end

  defp normalize_assign_target(var) when is_binary(var) do
    resolve_result_slot(var)
  end

  @doc """
  Before writing a new value into an owned slot under epilogue lifo outside loops,
  allocate a fresh owned slot instead of reusing the same index.

  Dynamic C loops may still reuse one slot per iteration; callers use
  `owned_reassign_prefix/1` there to release the prior iteration value.
  """
  @spec ensure_fresh_assign_target(String.t()) :: String.t()
  def ensure_fresh_assign_target(var) when is_binary(var) do
    var = normalize_assign_target(var)

    cond do
      RcRuntimeEmit.function_out_ref?(var) and epilogue_lifo?() and function_out_written?() ->
        {fresh, _} = alloc()
        fresh

      not epilogue_lifo?() ->
        var

      not owned_ref?(var) ->
        var

      in_c_loop?() ->
        var

      not slot_written?(var) ->
        var

      true ->
        {fresh, _} = alloc()
        slots = slots_state()

        if var == Map.get(slots, :result_slot_root) or var == Map.get(slots, :result_slot_current) do
          Process.put(:elmc_value_slots, Map.put(slots, :result_slot_current, fresh))
        end

        fresh
    end
  end

  @doc false
  @spec function_out_written?() :: boolean()
  def function_out_written?, do: Map.get(slots_state(), :function_out_written, false)

  @doc false
  @spec mark_function_out_written() :: :ok
  def mark_function_out_written do
    Process.put(:elmc_value_slots, Map.put(slots_state(), :function_out_written, true))
    :ok
  end

  @doc false
  @spec reset_function_out_written() :: :ok
  def reset_function_out_written do
    Process.put(:elmc_value_slots, Map.put(slots_state(), :function_out_written, false))
    :ok
  end

  @doc false
  @spec normalize_branch_result_slot(String.t()) :: String.t()
  def normalize_branch_result_slot(out) when is_binary(out) do
    flush = flush_deferred_nulls()

    slots = slots_state()
    root = Map.get(slots, :result_slot_root)
    current = Map.get(slots, :result_slot_current)

    final_normalize =
      cond do
        RcRuntimeEmit.function_out_ref?(out) and function_out_written?() ->
          ""

        RcRuntimeEmit.function_out_ref?(out) and is_binary(current) and
            not RcRuntimeEmit.function_out_ref?(current) ->
          stmt = RcRuntimeEmit.publish_function_out_from(current)
          Process.put(:elmc_value_slots, Map.put(slots, :result_slot_current, out))
          stmt

        not is_binary(root) or root != out or not is_binary(current) or current == root ->
          ""

        true ->
          stmt = RcRuntimeEmit.transfer_assignment(root, current)
          Process.put(:elmc_value_slots, Map.put(slots, :result_slot_current, root))
          stmt
      end

    if is_binary(root) and root == out do
      slots = slots_state()

      Process.put(:elmc_value_slots, %{
        slots
        | result_slot_root: nil,
          result_slot_current: nil
      })
    end

    join_stmts([flush, final_normalize])
  end

  @doc """
  Release a prior loop-iteration value before reusing an owned slot inside a C loop.
  Sequential assigns outside loops use `ensure_fresh_assign_target/1` instead.
  """
  @spec owned_reassign_prefix(String.t()) :: String.t()
  def owned_reassign_prefix(var) when is_binary(var) do
    with true <- owned_ref?(var),
         true <- epilogue_lifo?(),
         true <- in_c_loop?(),
         index when is_integer(index) <- owned_index(var) do
      slots = slots_state()

      if MapSet.member?(slots.written, index) do
        release_owned_eager(var) <> "\n"
      else
        ""
      end
    else
      _ -> ""
    end
  end

  defp slot_written?(var) when is_binary(var) do
    case owned_index(var) do
      index when is_integer(index) -> MapSet.member?(slots_state().written, index)
      _ -> false
    end
  end

  @doc "Mark codegen entering a C loop whose body may reassign owned slots each iteration."
  @spec push_loop() :: :ok
  def push_loop do
    slots = slots_state()
    Process.put(:elmc_value_slots, Map.put(slots, :loop_depth, Map.get(slots, :loop_depth, 0) + 1))
    :ok
  end

  @doc "Mark codegen leaving a C loop started with `push_loop/0`."
  @spec pop_loop() :: :ok
  def pop_loop do
    slots = slots_state()
    depth = max(Map.get(slots, :loop_depth, 0) - 1, 0)
    Process.put(:elmc_value_slots, Map.put(slots, :loop_depth, depth))
    :ok
  end

  @doc false
  @spec in_c_loop?() :: boolean()
  def in_c_loop?, do: Map.get(slots_state(), :loop_depth, 0) > 0

  @doc "Record that an owned slot now holds a value (for reassign-prefix tracking)."
  @spec mark_written(String.t()) :: :ok
  def mark_written(var) when is_binary(var) do
    case owned_index(var) do
      index when is_integer(index) ->
        slots = slots_state()
        Process.put(:elmc_value_slots, %{slots | written: MapSet.put(slots.written, index)})

      _ ->
        :ok
    end

    :ok
  end

  @spec unmark_written(String.t()) :: :ok
  defp unmark_written(var) when is_binary(var) do
    case owned_index(var) do
      index when is_integer(index) ->
        slots = slots_state()

        Process.put(:elmc_value_slots, %{
          slots
          | written: MapSet.delete(slots.written, index)
        })

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Release a value consumed mid-body. With epilogue lifo, owned scratch is left for
  `elmc_release_array_lifo`; loops that reuse a slot should call `release_owned_eager/1`.
  """
  @spec release_consumed(String.t()) :: String.t()
  def release_consumed(var) when is_binary(var) do
    if owned_ref?(var) do
      release_owned_and_null(var)
    else
      release_stmt(var)
    end
  end

  @doc """
  Emit epilogue cleanup plus a safe return when `body_var` may still live in `owned[]`.
  """
  @spec catch_return_epilogue(String.t(), String.t()) :: String.t()
  def catch_return_epilogue(body_var, cleanup) when is_binary(body_var) and is_binary(cleanup) do
    return_var =
      if owned_ref?(body_var) do
        "elmc_return_val"
      else
        body_var
      end

    save =
      if owned_ref?(body_var) do
        """
        ElmcValue *#{return_var} = #{body_var};
        #{null_assignment(body_var)}
        """
      else
        ""
      end

    cleanup_line = if cleanup == "", do: "", else: "#{cleanup}\n"

    """
    #{save}#{cleanup_line}if (Rc != RC_SUCCESS)
      return NULL;
    return #{return_var};
    """
    |> String.trim_trailing()
  end

  @spec failure_cleanup_for_vars_list([String.t()]) :: String.t()
  def failure_cleanup_for_vars_list(_vars), do: failure_cleanup()

  @spec transfer_and_null(String.t()) :: String.t()
  def transfer_and_null(var) when is_binary(var) do
    transfer(var)
    unmark_written(var)

    cond do
      RcRuntimeEmit.function_out_ref?(var) ->
        ""

      defer_nulls?() and owned_ref?(var) ->
        queue_deferred_null(var)
        ""

      true ->
        finalize_transferred_null(var)
    end
  end

  @doc false
  @spec flush_deferred_nulls() :: String.t()
  def flush_deferred_nulls do
    slots = slots_state()
    max_slot = slot_count()

    vars =
      Map.get(slots, :deferred_nulls, [])
      |> Enum.filter(fn var ->
        case owned_index(var) do
          index when is_integer(index) -> index < max_slot
          _ -> false
        end
      end)

    {code, _} =
      Enum.reduce(vars, {"", slots}, fn var, {acc, _slots} ->
        stmt = finalize_transferred_null(var)
        {join_stmts([acc, stmt]), slots_state()}
      end)

    Process.put(:elmc_value_slots, Map.put(slots_state(), :deferred_nulls, []))
    code
  end

  @doc false
  @spec materialize_tuple_projections_of_dest(String.t()) :: String.t()
  def materialize_tuple_projections_of_dest(dest_var) when is_binary(dest_var) do
    case owned_index(dest_var) do
      dest_index when is_integer(dest_index) ->
        slots = slots_state()

        {stmts, projections} =
          Enum.reduce(slots.tuple_projections, {[], slots.tuple_projections}, fn
            {src, {^dest_index, which}}, {acc, proj} ->
              tuple_fn =
                case which do
                  :first -> "elmc_tuple_first"
                  :second -> "elmc_tuple_second"
                end

              stmt = "#{ref(src)} = elmc_retain(#{tuple_fn}(#{ref(dest_index)}));"
              slots = slots_state()

              slots = %{
                slots
                | live: MapSet.put(slots.live, src),
                  transferred: MapSet.delete(slots.transferred, src),
                  deferred_nulls: List.delete(Map.get(slots, :deferred_nulls, []), ref(src))
              }

              Process.put(:elmc_value_slots, slots)
              {acc ++ [stmt], Map.delete(proj, src)}

            _, acc_proj ->
              acc_proj
          end)

        Process.put(:elmc_value_slots, Map.put(slots_state(), :tuple_projections, projections))
        join_stmts(stmts)

      _ ->
        ""
    end
  end

  defp finalize_transferred_null(var) when is_binary(var) do
    cond do
      RcRuntimeEmit.function_out_ref?(var) ->
        ""

      owned_ref?(var) or RcRuntimeEmit.fresh_owned_slot?(var) ->
        normalize = maybe_normalize_result_slot_before_null(var)

        null =
          if normalize != "" do
            ""
          else
            null_assignment(var)
          end

        join_stmts([
          normalize,
          null
        ])

      true ->
        ""
    end
  end

  defp maybe_normalize_result_slot_before_null(var) when is_binary(var) do
    slots = slots_state()
    root = Map.get(slots, :result_slot_root)
    current = Map.get(slots, :result_slot_current)

    if owned_ref?(var) and is_binary(root) and is_binary(current) and var == current and
         root != current do
      stmt = RcRuntimeEmit.transfer_assignment(root, current)
      Process.put(:elmc_value_slots, Map.put(slots_state(), :result_slot_current, root))
      stmt
    else
      ""
    end
  end

  defp defer_nulls? do
    epilogue_lifo?() and is_binary(Map.get(slots_state(), :result_slot_root))
  end

  defp queue_deferred_null(var) when is_binary(var) do
    slots = slots_state()
    deferred = Map.get(slots, :deferred_nulls, [])

    if var in deferred do
      :ok
    else
      Process.put(:elmc_value_slots, Map.put(slots, :deferred_nulls, deferred ++ [var]))
    end

    :ok
  end

  defp join_stmts(stmts) when is_list(stmts) do
    stmts
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  @spec transfer_and_null_refs([String.t()]) :: String.t()
  def transfer_and_null_refs(refs) when is_list(refs) do
    refs
    |> Enum.map(&transfer_and_null/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n")
  end

  # Backward-compatible alias used by case branches that drop branch-local temps.
  @spec untrack(String.t()) :: :ok
  def untrack(var) when is_binary(var), do: release(var)

  defp slots_state do
    Process.get(:elmc_value_slots, %{
      next: 0,
      live: MapSet.new(),
      transferred: MapSet.new(),
      tuple_projections: %{},
      written: MapSet.new(),
      loop_depth: 0,
      epilogue_lifo: false,
      direct_param_owned: %{},
      result_slot_root: nil,
      result_slot_current: nil,
      deferred_nulls: []
    })
  end
end
