defmodule Elmx.SpecialValuesElmcConformanceTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Pebble.KernelTargets
  alias Elmx.Runtime.Pebble.SpecialValues

  @elmc_codegen Path.expand("../../elmc/lib/elmc/backend/c_codegen.ex", __DIR__)
  @target_re ~r/defp special_value_from_target\("([^"]+)"/

  # Handled by `Elmx.Runtime.Stdlib.Qualified` / `Elmx.Runtime.Json.Decode`, not `SpecialValues`.
  @emit_or_stdlib_targets MapSet.new([
                            "Basics.abs",
                            "Basics.always",
                            "Basics.clamp",
                            "Basics.identity",
                            "Basics.max",
                            "Basics.min",
                            "Basics.modBy",
                            "Basics.negate",
                            "Basics.not",
                            "Basics.remainderBy",
                            "Basics.sqrt",
                            "Basics.toFloat",
                            "List.concat",
                            "List.filter",
                            "List.foldl",
                            "List.head",
                            "List.isEmpty",
                            "List.length",
                            "List.map",
                            "List.maximum",
                            "List.minimum",
                            "List.product",
                            "List.reverse",
                            "List.sort",
                            "List.sum",
                            "List.tail"
                          ])

  # elmc maps these in C codegen but elmx routes through kernel dispatch instead.
  @kernel_only_gaps MapSet.new([
                      "Elm.Kernel.Random.generate"
                    ])

  @json_decode_prefix "Json.Decode."

  test "elmx rewrites every elmc special_value target in SpecialValues scope" do
    elmc_targets = elmc_special_value_targets()
    in_scope = Enum.filter(elmc_targets, &special_values_scope?/1)
    missing = Enum.reject(in_scope, &elmx_handles_target?/1)

    assert missing == [],
           """
           elmx SpecialValues missing #{length(missing)} elmc target(s):
           #{Enum.join(missing, "\n")}
           """
  end

  test "canonical import shorthands stay in scope" do
    assert special_values_scope?("Cmd.none")
    assert special_values_scope?("Sub.batch")
    assert elmx_handles_target?("Cmd.none")
  end

  defp elmc_special_value_targets do
    @elmc_codegen
    |> File.read!()
    |> then(&Regex.scan(@target_re, &1, capture: :all_but_first))
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp special_values_scope?(target) do
    canonical = SpecialValues.canonical_target(target)

    cond do
      MapSet.member?(@emit_or_stdlib_targets, target) ->
        false

      String.starts_with?(target, @json_decode_prefix) ->
        false

      String.starts_with?(canonical, "Platform.") ->
        true

      String.starts_with?(canonical, "Pebble.") ->
        true

      String.starts_with?(canonical, "Json.") ->
        true

      String.starts_with?(canonical, "Companion.") ->
        true

      canonical == "List.cons" ->
        true

      String.starts_with?(canonical, "Elm.Kernel.PebbleWatch.") ->
        true

      String.starts_with?(canonical, "Elm.Kernel.PebblePhone.") ->
        true

      true ->
        false
    end
  end

  defp elmx_handles_target?(target) do
    canonical = SpecialValues.canonical_target(target)
    args = conformance_args(canonical)

    if MapSet.member?(@kernel_only_gaps, canonical) do
      true
    else
      case SpecialValues.rewrite(canonical, args) do
        {:ok, _} ->
          true

        :error ->
          kernel_handles?(canonical, args)
      end
    end
  end

  defp conformance_args("Pebble.Ui.Color.indexed"), do: [%{op: :int_literal, value: 0}]
  defp conformance_args("Pebble.Ui.Color.toInt"), do: [%{op: :int_literal, value: 0}]
  defp conformance_args("Pebble.Cmd.batch"), do: [%{op: :list_literal, items: []}]
  defp conformance_args("Platform.Cmd.batch"), do: [%{op: :list_literal, items: []}]
  defp conformance_args("Pebble.Events.batch"), do: [%{op: :list_literal, items: []}]
  defp conformance_args("Platform.Sub.batch"), do: [%{op: :list_literal, items: []}]
  defp conformance_args("Cmd.batch"), do: [%{op: :list_literal, items: []}]
  defp conformance_args("Sub.batch"), do: [%{op: :list_literal, items: []}]
  defp conformance_args("Pebble.Ui.windowStack"), do: [%{op: :list_literal, items: []}]
  defp conformance_args("Pebble.Ui.window"), do: [%{op: :int_literal, value: 0}, %{op: :list_literal, items: []}]
  defp conformance_args("Pebble.Ui.canvasLayer"), do: [%{op: :int_literal, value: 0}, %{op: :list_literal, items: []}]
  defp conformance_args(_), do: []

  defp kernel_handles?(target, args) do
    case KernelTargets.rewrite(target, args) do
      {:ok, _} -> true
      :error -> false
    end
  end

end
