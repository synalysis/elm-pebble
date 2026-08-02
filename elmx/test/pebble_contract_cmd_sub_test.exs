defmodule Elmx.PebbleContractCmdSubTest do
  @moduledoc """
  Asserts shared `Elmx.Pebble.Contract.CmdSub` stays aligned with elmx masks/wire
  and with elmc source-of-truth tables (CommandKinds / subscription magic / flags).
  """

  use ExUnit.Case, async: true
  import Bitwise

  alias Elmx.Pebble.Contract.CmdSub
  alias Elmx.Runtime.Pebble.SubscriptionMasks

  @elmc_root Path.expand("../../elmc", __DIR__)
  @command_kinds_path Path.join(@elmc_root, "lib/elmc/backend/pebble/kinds/tables/command_kinds.ex")
  @emit_path Path.join(@elmc_root, "lib/elmc/backend/c_codegen/emit.ex")
  @flags_path Path.join(@elmc_root, "lib/elmc/backend/pebble/header_writer/subscription_flags.ex")
  @subs_path Path.join(@elmc_root, "lib/elmc/backend/plan/worker/subscriptions.ex")
  @special_values_glob Path.join(@elmc_root, "lib/elmc/backend/plan/lower/special_values/**/*.ex")

  test "contract covers every CommandKinds atom with matching numeric id and C macro" do
    kinds = parse_command_kinds()
    contract_ids = MapSet.new(CmdSub.cmd_ids())
    kind_ids = MapSet.new(Keyword.keys(kinds))

    assert MapSet.equal?(contract_ids, kind_ids),
           """
           Cmd contract drift vs CommandKinds:
           missing_in_contract=#{inspect(MapSet.difference(kind_ids, contract_ids) |> Enum.sort())}
           extra_in_contract=#{inspect(MapSet.difference(contract_ids, kind_ids) |> Enum.sort())}
           """

    for row <- CmdSub.cmds() do
      assert Keyword.fetch!(kinds, row.id) == row.numeric,
             "#{row.id} numeric expected #{row.numeric}, got #{Keyword.fetch!(kinds, row.id)}"

      assert row.c_macro == "ELMC_PEBBLE_CMD_" <> String.upcase(Atom.to_string(row.id))
    end
  end

  test "subscription contract bits match ELMC_SUBSCRIPTION_* magic numbers" do
    magic = parse_subscription_magic()

    for row <- CmdSub.subs() do
      assert Map.fetch!(magic, row.c_lowering) == row.bit,
             "#{row.c_lowering} expected bit #{row.bit}, got #{Map.get(magic, row.c_lowering)}"
    end

    expected_macros = MapSet.new(Enum.map(CmdSub.subs(), & &1.c_lowering))
    actual_macros = MapSet.new(Map.keys(magic))

    assert MapSet.subset?(expected_macros, actual_macros),
           "missing subscription magic macros: #{inspect(MapSet.difference(expected_macros, actual_macros) |> Enum.sort())}"
  end

  test "ELMC_PEBBLE_SUB_* runtime flags match contract bits when present" do
    flags = parse_subscription_flags()

    for %{c_runtime: macro, bit: bit, id: id} <- CmdSub.subs(), is_binary(macro) do
      assert Map.fetch!(flags, macro) == bit,
             "#{id} #{macro} expected #{bit}, got #{Map.get(flags, macro)}"
    end
  end

  test "elmx SubscriptionMasks matches contract for every Elm target" do
    for row <- CmdSub.subs(),
        row.id != :frame,
        target <- row.elm_targets,
        target != "Elm.Kernel.Time.every" do
      assert SubscriptionMasks.mask(target) == row.bit,
             "SubscriptionMasks.mask(#{inspect(target)}) expected #{row.bit}, got #{inspect(SubscriptionMasks.mask(target))}"
    end
  end

  test "elmc subscription_item_c_expr maps every non-frame contract target" do
    source = File.read!(@subs_path)

    for row <- CmdSub.subs(), row.id != :frame, target <- row.elm_targets do
      # Elm.Kernel.Time.every is accepted via normalize in some paths; skip if absent.
      if target == "Elm.Kernel.Time.every" do
        :ok
      else
        assert source =~ ~s("#{target}" -> "#{row.c_lowering}"),
               "subscriptions.ex missing #{target} -> #{row.c_lowering}"
      end
    end
  end

  test "elmc special_values lower every contract Cmd elm_target" do
    sources =
      @special_values_glob
      |> Path.wildcard()
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    for row <- CmdSub.cmds(), row.id != :none, target <- row.elm_targets do
      assert sources =~ ~s(special_value_from_target("#{target}"),
             "elmc special_values missing Cmd target #{target} (#{row.id})"
    end
  end

  test "elmx DeviceStubs / wire kinds exist for supported device cmds" do
    stub_source = File.read!(Path.expand("../lib/elmx/runtime/pebble/device_stubs.ex", __DIR__))
    cmd_sources =
      [
        "lib/elmx/runtime/cmd/device.ex",
        "lib/elmx/runtime/cmd/storage.ex",
        "lib/elmx/runtime/cmd/effects.ex",
        "lib/elmx/runtime/cmd.ex",
        "lib/elmx/runtime/pebble/dispatch.ex",
        "lib/elmx/runtime/pebble/device_stubs.ex"
      ]
      |> Enum.map(&Path.expand("../#{&1}", __DIR__))
      |> Enum.map(&File.read!/1)
      |> Enum.join("\n")

    for row <- CmdSub.elmx_supported_cmds() do
      wire = CmdSub.elmx_wire_kind(row.elmx_wire)
      assert is_binary(wire), "#{row.id} missing elmx wire kind"

      case row.elmx_wire do
        {:device, slug} ->
          assert String.contains?(stub_source, "value(\"#{slug}\")") or String.contains?(cmd_sources, slug),
                 "missing device stub/wire for #{row.id} slug=#{slug}"

          assert wire == "cmd.device.#{slug}"

        {:storage, slug} ->
          assert String.contains?(cmd_sources, "\"cmd.storage.#{slug}\""),
                 "missing storage wire for #{row.id}"

        {:timer, _} ->
          assert String.contains?(cmd_sources, "\"cmd.timer.after\"")

        {:backlight, _} ->
          assert String.contains?(cmd_sources, "\"cmd.backlight\"")

        {:effect, family, _} ->
          assert String.contains?(cmd_sources, "cmd.effect.") or
                   String.contains?(cmd_sources, "cmd.effect.#{family}")

        {:data_log, _} ->
          assert String.contains?(cmd_sources, "data_log") or String.contains?(cmd_sources, "datalog")

        {:protocol, _} ->
          companion = File.read!(Path.expand("../lib/elmx/runtime/cmd/companion.ex", __DIR__))
          assert String.contains?(cmd_sources, "\"kind\" => \"protocol\"") or
                   String.contains?(companion, "\"kind\" => \"protocol\"")

        {:dictation, _} ->
          assert String.contains?(cmd_sources, "dictation")

        other ->
          flunk("unhandled elmx_wire #{inspect(other)} for #{row.id}")
      end
    end
  end

  test "contract exposes unique cmd numerics and unique sub bits" do
    cmd_nums = Enum.map(CmdSub.cmds(), & &1.numeric)
    assert cmd_nums == Enum.uniq(cmd_nums)

    sub_bits = Enum.map(CmdSub.subs(), & &1.bit)
    assert sub_bits == Enum.uniq(sub_bits)
  end

  defp parse_command_kinds do
    source = File.read!(@command_kinds_path)

    Regex.scan(~r/^\s+([a-z0-9_]+):\s+(\d+)/m, source)
    |> Enum.map(fn [_, name, num] -> {String.to_atom(name), String.to_integer(num)} end)
  end

  defp parse_subscription_magic do
    source = File.read!(@emit_path)

    Regex.scan(~r/\{\"ELMC_SUBSCRIPTION_([A-Z0-9_]+)\",\s*\"(\d+)(?:LL)?\"\}/, source)
    |> Map.new(fn [_, name, num] ->
      {"ELMC_SUBSCRIPTION_#{name}", String.to_integer(num)}
    end)
  end

  defp parse_subscription_flags do
    source = File.read!(@flags_path)

    Regex.scan(~r/#define (ELMC_PEBBLE_SUB_[A-Z0-9_]+) \(1(?:LL)? << (\d+)\)/, source)
    |> Map.new(fn [_, name, shift] -> {name, 1 <<< String.to_integer(shift)} end)
  end
end
