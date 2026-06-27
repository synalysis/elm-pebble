defmodule Elmc.Backend.CCodegen.ValueSlots do
  @moduledoc false

  alias Elmc.Backend.CCodegen.OwnershipTransfer

  @owned_ref ~r/^owned\[(\d+)\]$/

  @spec reset() :: :ok
  def reset do
    Process.put(:elmc_value_slots, %{
      next: 0,
      live: MapSet.new(),
      transferred: MapSet.new()
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
  Emit a release for `var`. Owned slots use `ELMC_RELEASE` so failure cleanup
  via `elmc_release_array_lifo` cannot double-free after an early release.
  """
  @spec release_stmt(String.t()) :: String.t()
  def release_stmt(var) when is_binary(var) do
    if owned_ref?(var) do
      release(var)
      "ELMC_RELEASE(#{var});"
    else
      "elmc_release(#{var});"
    end
  end

  @spec null_assignment(String.t() | non_neg_integer()) :: String.t()
  def null_assignment(var) when is_binary(var) do
    "#{var} = NULL;"
  end

  def null_assignment(index) when is_integer(index), do: null_assignment(ref(index))

  @spec boxed_decl(String.t(), String.t()) :: String.t()
  def boxed_decl(var, rhs) when is_binary(var) and is_binary(rhs) do
    if owned_ref?(var) do
      "#{var} = #{rhs};"
    else
      "ElmcValue *#{var} = #{rhs};"
    end
  end

  @spec boxed_null_decl(String.t()) :: String.t()
  def boxed_null_decl(var) when is_binary(var) do
    if owned_ref?(var), do: "#{var} = NULL;", else: "ElmcValue *#{var} = NULL;"
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
    if slot_count() == 0 do
      ""
    else
      "elmc_release_array_lifo(owned, DIM(owned));"
    end
  end

  @spec failure_cleanup_for_vars_list([String.t()]) :: String.t()
  def failure_cleanup_for_vars_list(_vars), do: failure_cleanup()

  @spec transfer_and_null(String.t()) :: String.t()
  def transfer_and_null(var) when is_binary(var) do
    transfer(var)

    if owned_ref?(var) do
      null_assignment(var)
    else
      ""
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
    Process.get(:elmc_value_slots, %{next: 0, live: MapSet.new(), transferred: MapSet.new()})
  end
end
