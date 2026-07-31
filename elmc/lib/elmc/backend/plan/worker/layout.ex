defmodule Elmc.Backend.Plan.Worker.Layout do
  @moduledoc """
  Plan-owned subscription layout metadata for the Elm worker TEA host.

  Consumes mask analysis from `Plan.Worker.Subscriptions` and produces a compact
  slot map (`sub_tag_slots`, `button_raw_subs`, `slot_map`, `frame_slot`).

  Worker adapter emission runs **before** full C codegen; Msg constructor names
  must be seeded here (`with_msg_constructor_names/3`) so bare constructor_ref
  tags resolve during compact layout analysis.
  """
  alias Elmc.Backend.Plan.Worker.Subscriptions
  alias Elmc.Backend.Pebble.IRAnalysis
  alias ElmEx.IR

  @fallback_sub_tag_slots 32
  # Dynamic layouts used to reserve 16 button-raw slots (~192 B BSS). Watch apps
  # rarely need that many concurrent raw button bindings.
  @fallback_button_raw_subs 4

  @type t :: Subscriptions.worker_subscription_layout()

  @spec analyze(IR.t(), String.t()) :: t()
  def analyze(%IR{} = ir, entry_module) do
    with_msg_constructor_names(ir, entry_module, fn ->
      case subscriptions_expr(ir, entry_module) do
        nil ->
          %{
            tag_masks: [],
            button_raw_count: 0,
            compact: true,
            has_frame: false,
            model_dependent?: false,
            slot_map: %{},
            frame_slot: nil,
            sub_tag_slots: 1,
            button_raw_subs: 1
          }

        expr ->
          decl = subscriptions_decl(ir, entry_module)

          expr
          |> Subscriptions.analyze_subscription_masks()
          |> Map.put(:model_dependent?, Subscriptions.model_dependent?(decl))
          |> build_slot_layout()
      end
    end)
  end

  @spec with_msg_constructor_names(IR.t(), String.t(), (-> term())) :: term()
  defp with_msg_constructor_names(%IR{} = ir, entry_module, fun) when is_function(fun, 0) do
    previous = Process.get(:elmc_pebble_msg_names)

    msg_names =
      ir
      |> IRAnalysis.msg_constructors(entry_module)
      |> Enum.map(&elem(&1, 0))
      |> MapSet.new()

    Process.put(:elmc_pebble_msg_names, msg_names)

    try do
      fun.()
    after
      if is_nil(previous) do
        Process.delete(:elmc_pebble_msg_names)
      else
        Process.put(:elmc_pebble_msg_names, previous)
      end
    end
  end

  defp subscriptions_decl(%IR{} = ir, entry_module) do
    ir.modules
    |> Enum.find_value(fn mod ->
      if mod.name == entry_module do
        mod.declarations
        |> Enum.find_value(fn
          %{kind: :function, name: "subscriptions"} = decl -> decl
          _ -> nil
        end)
      end
    end)
  end

  defp subscriptions_expr(%IR{} = ir, entry_module) do
    case subscriptions_decl(ir, entry_module) do
      %{expr: expr} when not is_nil(expr) -> expr
      %{body: body} when not is_nil(body) -> body
      _ -> nil
    end
  end

  defp build_slot_layout(%{compact: false} = analysis) do
    diagnostic = %{
      "severity" => "warning",
      "source" => "elmc/subscriptions",
      "code" => "dynamic_subscription_layout",
      "message" =>
        "Worker subscription layout could not be compacted; using fallback " <>
          "ELMC_WORKER_SUB_TAG_SLOTS=#{@fallback_sub_tag_slots} and " <>
          "ELMC_WORKER_MAX_BUTTON_RAW_SUBS=#{@fallback_button_raw_subs}. " <>
          "Prefer a statically enumerable Events.batch / if-else Sub tree so " <>
          "the worker can use a dense slot map."
    }

    warnings = Process.get(:elmc_compile_warnings, [])
    Process.put(:elmc_compile_warnings, [diagnostic | warnings])

    Map.merge(analysis, %{
      slot_map: %{},
      frame_slot: nil,
      sub_tag_slots: @fallback_sub_tag_slots,
      button_raw_subs: max(analysis.button_raw_count, @fallback_button_raw_subs)
    })
  end

  defp build_slot_layout(%{tag_masks: tag_masks, has_frame: has_frame} = analysis) do
    {slot_map, next_index} =
      Enum.map_reduce(tag_masks, 0, fn mask, index ->
        name = slot_define_name(mask)
        {{mask, {name, index}}, index + 1}
      end)
      |> then(fn {pairs, next_index} -> {Map.new(pairs), next_index} end)

    frame_slot = if has_frame, do: next_index, else: nil
    button_raw_subs = max(analysis.button_raw_count, 1)

    needs_frame_slot? =
      has_frame or
        (analysis.button_raw_count >= 3 and tag_masks == [])

    frame_slot = if needs_frame_slot?, do: frame_slot || next_index, else: frame_slot
    sub_tag_slots = next_index + if(needs_frame_slot?, do: 1, else: 0) |> max(1)

    Map.merge(analysis, %{
      slot_map: slot_map,
      frame_slot: frame_slot,
      sub_tag_slots: sub_tag_slots,
      button_raw_subs: button_raw_subs
    })
  end

  defp slot_define_name(mask) when is_binary(mask) do
    mask
    |> String.replace_prefix("ELMC_SUBSCRIPTION_", "ELMC_WORKER_SLOT_")
    |> String.replace(~r/[^A-Z0-9_]/, "_")
    |> String.trim("_")
  end
end
