defmodule Elmc.PebbleContractCmdSubParityTest do
  @moduledoc """
  Live elmc API parity against shared `Elmx.Pebble.Contract.CmdSub`.

  Locks Elm targets → `ELMC_PEBBLE_CMD_*` / `ELMC_SUBSCRIPTION_*` constants so
  debugger (elmx) and generated C stay on the same contract.
  """

  use ExUnit.Case, async: true

  alias Elmc.Backend.Pebble.CEmit
  alias Elmc.Backend.Pebble.HeaderWriter.SubscriptionFlags
  alias Elmc.Backend.Pebble.Kinds
  alias Elmc.Backend.Plan.Worker.Subscriptions
  alias Elmx.Pebble.Contract.CmdSub

  test "CommandKinds table matches shared Cmd contract" do
    table = Map.new(Kinds.command_kinds())

    assert MapSet.new(Map.keys(table)) == MapSet.new(CmdSub.cmd_ids())

    for row <- CmdSub.cmds() do
      assert table[row.id] == row.numeric
      assert Kinds.command_kind_c_name!(row.id) == row.c_macro
    end
  end

  test "generated C command enum contains every contract macro=numeric" do
    enum_c = CEmit.c_enum("ElmcPebbleCommandKind", "ELMC_PEBBLE_CMD", Kinds.command_kinds())

    for row <- CmdSub.cmds() do
      assert enum_c =~ "#{row.c_macro} = #{row.numeric}",
             "C enum missing #{row.c_macro} = #{row.numeric}"
    end
  end

  test "SubscriptionFlags header contains every contract ELMC_PEBBLE_SUB_* bit" do
    flags = SubscriptionFlags.body()

    for %{c_runtime: macro, bit: bit, id: id} <- CmdSub.subs(), is_binary(macro) do
      shift = bit_shift(bit)
      assert flags =~ macro,
             "SubscriptionFlags missing #{macro} for #{id}"

      assert flags =~ "#{macro} (1" and (flags =~ "<< #{shift})" or flags =~ "<< #{shift})"),
             "#{macro} should use shift #{shift} (bit=#{bit})"
    end
  end

  test "subscription lowering maps every non-frame Elm target to contract mask macro" do
    for row <- CmdSub.subs(), row.id != :frame, target <- row.elm_targets do
      if target in ["Elm.Kernel.Time.every"] do
        :ok
      else
        expr = subscription_mask_expr(target)
        assert expr == row.c_lowering,
               "Subscriptions.single_subscription_expr(#{inspect(target)}) => #{inspect(expr)}, expected #{row.c_lowering}"
      end
    end
  end

  test "frame subscription encodes FRAME_BASE with interval" do
    ms_arg = %{op: :int_literal, value: 33}

    assert %{op: :pebble_sub, mask: %{op: :c_int_expr, value: expr}} =
             Subscriptions.single_subscription_expr("Pebble.Frame.every", [ms_arg, msg_tag()])

    assert expr =~ "ELMC_SUBSCRIPTION_FRAME_BASE"
  end

  defp bit_shift(bit) when bit > 0 do
    bit
    |> :math.log2()
    |> trunc()
  end

  # union_ctor bypasses compile-time Msg-tag registry checks in constructor_tag_expr/1.
  defp msg_tag, do: %{op: :int_literal, union_ctor: "Tick", value: 0}

  defp subscription_mask_expr(target) do
    args = subscription_args(target)

    case Subscriptions.single_subscription_expr(target, args) do
      %{op: :pebble_sub, mask: %{op: :c_int_expr, value: value}} when is_binary(value) ->
        value

      other ->
        flunk("expected pebble_sub mask for #{target}, got #{inspect(other)}")
    end
  end

  defp subscription_args(target) do
    cond do
      target in ~w(Pebble.Button.onPress Pebble.Button.onRelease Pebble.Button.onLongPress) ->
        [%{op: :c_int_expr, value: "ELMC_BUTTON_UP"}, msg_tag()]

      target in ~w(Pebble.Button.on Elm.Kernel.PebbleWatch.onButtonRaw) ->
        [
          %{op: :c_int_expr, value: "ELMC_BUTTON_UP"},
          # pressed = 1 (button_event_int_expr accepts int_literal only)
          %{op: :int_literal, value: 1},
          msg_tag()
        ]

      true ->
        [msg_tag()]
    end
  end
end
