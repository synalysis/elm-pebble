defmodule Elmc.Backend.C.Lower.Frame do
  @moduledoc false

  alias Elmc.Backend.Plan.Types
  alias Elmc.Backend.Plan.Types.FunctionPlan

  @heap_owned_slot_threshold 23

  @spec owned_declaration(FunctionPlan.t(), Types.slot_map()) :: String.t()
  def owned_declaration(%FunctionPlan{} = plan, slots) do
    count = owned_slot_count(slots)

    cond do
      count == 0 -> ""
      heap_owned?(count) -> heap_owned_declaration(count, plan.rc_required)
      true -> "ElmcValue *owned[#{count}] = {0};"
    end
  end

  @spec epilogue_release([non_neg_integer()], non_neg_integer()) :: String.t()
  def epilogue_release([], _slot_count), do: ""

  def epilogue_release(slot_indices, slot_count) do
    if heap_owned?(slot_count) do
      "elmc_release_array_lifo(owned, ELMC_OWNED_SLOT_COUNT);\nelmc_free(owned);"
    else
      "elmc_release_array_lifo(owned, #{length(slot_indices)});"
    end
  end

  @spec wrap_catch(boolean(), String.t()) :: String.t()
  def wrap_catch(true, body) do
    """
    CATCH_BEGIN
    #{body}
    CATCH_END;
    """
  end

  def wrap_catch(false, body), do: body

  defp owned_slot_count(slots) do
    case Map.values(slots) do
      [] -> 0
      values -> Enum.max(values) + 1
    end
  end

  defp heap_owned?(slot_count) do
    slot_count >= @heap_owned_slot_threshold and pebble_int32_build?()
  end

  defp pebble_int32_build? do
    Process.get(:elmc_codegen_opts, %{})[:pebble_int32] == true
  end

  defp heap_owned_declaration(slot_count, rc?) do
    ret =
      if rc? do
        "return RC_ERR_OUT_OF_MEMORY;"
      else
        "return elmc_int_zero();"
      end

    """
    enum { ELMC_OWNED_SLOT_COUNT = #{slot_count} };
    ElmcValue **owned = (ElmcValue **)elmc_calloc(ELMC_OWNED_SLOT_COUNT, sizeof(ElmcValue *), "owned_slots");
    if (!owned) #{ret}
    """
    |> String.trim()
  end
end
