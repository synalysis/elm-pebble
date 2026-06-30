defmodule Elmc.Backend.CCodegen.ValueSlots do
  @moduledoc false

  alias Elmc.Backend.CCodegen.OwnershipTransfer
  alias Elmc.Backend.CCodegen.RcRuntimeEmit

  @owned_ref ~r/^owned\[(\d+)\]$/

  @spec reset(keyword()) :: :ok
  def reset(opts \\ []) do
    Process.put(:elmc_value_slots, %{
      next: 0,
      live: MapSet.new(),
      transferred: MapSet.new(),
      tuple_projections: %{},
      epilogue_lifo: Keyword.get(opts, :epilogue_lifo, false)
    })

    :ok
  end

  @spec epilogue_lifo?() :: boolean()
  def epilogue_lifo? do
    Map.get(slots_state(), :epilogue_lifo, false)
  end

  @type snapshot :: %{
          transferred: MapSet.t(),
          tuple_projections: map(),
          live: MapSet.t()
        }

  @doc "Capture transfer/projection marks before a divergent branch (not slot indices)."
  @spec snapshot() :: snapshot()
  def snapshot do
    slots = slots_state()

    %{
      transferred: slots.transferred,
      tuple_projections: slots.tuple_projections,
      live: slots.live
    }
  end

  @doc "Restore transfer/projection marks so sibling branches start with a clean slate."
  @spec restore(snapshot()) :: :ok
  def restore(%{transferred: transferred, tuple_projections: tuple_projections, live: live}) do
    slots = slots_state()

    Process.put(:elmc_value_slots, %{
      slots
      | transferred: transferred,
        tuple_projections: tuple_projections,
        live: live
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
            if MapSet.member?(slots_state().transferred, dest) do
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
            "#{var} = #{rhs};"

          true ->
            "ElmcValue *#{var} = #{rhs};"
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
    case slot_count() do
      0 -> ""
      n -> "ElmcValue *owned[#{n}] = {0};"
    end
  end

  @spec failure_cleanup() :: String.t()
  def failure_cleanup do
    epilogue_cleanup()
  end

  @doc """
  Release still-live owned scratch slots in LIFO index order at function epilogue.
  Transferred slots are already nulled; untracked direct assignments are untouched.
  """
  @spec epilogue_cleanup() :: String.t()
  def epilogue_cleanup do
    case slot_count() do
      0 -> ""
      _ -> "elmc_release_array_lifo(owned, DIM(owned));"
    end
  end

  @doc """
  Release a call operand after the callee returns. Owned scratch in epilogue-lifo
  functions is left for `elmc_release_array_lifo`; transfers null the slot.
  """
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
    if epilogue_lifo?() do
      ""
    else
      release_owned_eager(var)
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

  @doc """
  Release a value consumed mid-body. Owned slots are always released eagerly so loop
  reuse cannot leak; temps use `elmc_release`. Compare operands and let epilogues that
  should defer to `elmc_release_array_lifo` use `release_owned_and_null/1` instead.
  """
  @spec release_consumed(String.t()) :: String.t()
  def release_consumed(var) when is_binary(var) do
    if owned_ref?(var) do
      release_owned_eager(var)
    else
      release_stmt(var)
    end
  end

  @spec failure_cleanup_for_vars_list([String.t()]) :: String.t()
  def failure_cleanup_for_vars_list(_vars), do: failure_cleanup()

  @spec transfer_and_null(String.t()) :: String.t()
  def transfer_and_null(var) when is_binary(var) do
    transfer(var)

    cond do
      RcRuntimeEmit.function_out_ref?(var) -> ""
      owned_ref?(var) -> null_assignment(var)
      true -> ""
    end
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
      epilogue_lifo: false
    })
  end
end
