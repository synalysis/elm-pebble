defmodule Elmc.CompanionCmdParamSlotsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CmdCompile
  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.ValueSlots

  setup do
    ValueSlots.reset(epilogue_lifo: true)
    :ok
  end

  defp watch_to_phone_int_decl(name, value) do
  %{
    name: name,
    args: ["message"],
    type: "WatchToPhone -> Int",
    ownership: [:borrow_arg, :borrow_result, :direct_call_abi],
    expr: %{
      op: :case,
      subject: %{op: :var, name: "message"},
      branches: [
        %{
          pattern: %{
            kind: :constructor,
            name: "RequestWeather",
            bind: "location",
            arg_pattern: %{kind: :var, name: "location"}
          },
          expr: %{op: :int_literal, value: value}
        }
      ]
    }
  }
  end

  defp companion_send_expr do
    %{
      op: :pebble_cmd,
      kind: %{op: :c_int_expr, value: "ELMC_PEBBLE_CMD_COMPANION_SEND"},
      params: [
        %{
          op: :qualified_call,
          target: "Companion.Internal.watchToPhoneTag",
          args: [%{op: :var, name: "message"}]
        },
        %{
          op: :qualified_call,
          target: "Companion.Internal.watchToPhoneValue",
          args: [%{op: :var, name: "message"}]
        }
      ]
    }
  end

  defp tail_env(decl_map) do
    %{
      "message" => "message",
      __module__: "Companion.Watch",
      __rc_catch__: true,
      __program_decls__: decl_map
    }
    |> RcRuntimeEmit.function_tail_env()
  end

  test "companionSend param calls use owned slots instead of function out under RC tail env" do
    decl_map = %{
      {"Companion.Internal", "watchToPhoneTag"} => watch_to_phone_int_decl("watchToPhoneTag", 2),
      {"Companion.Internal", "watchToPhoneValue"} => watch_to_phone_int_decl("watchToPhoneValue", 3)
    }

    Process.put(:elmc_program_decls, decl_map)

    {code, _out, _counter} = CmdCompile.compile(companion_send_expr(), tail_env(decl_map), 0)

    refute code =~ "(out,"
    refute code =~ "ELMC_FN_OUT"
    assert code =~ "watchToPhoneTag"
    assert code =~ "watchToPhoneValue"
    assert code =~ "owned[0]"
    assert code =~ "owned[1]"
    assert code =~ "elmc_cmd2(ELMC_PEBBLE_CMD_COMPANION_SEND"
  end

  test "sendWatchToPhone body keeps intermediate tag/value out of function out slot" do
    decl_map = %{
      {"Companion.Internal", "watchToPhoneTag"} => watch_to_phone_int_decl("watchToPhoneTag", 2),
      {"Companion.Internal", "watchToPhoneValue"} => watch_to_phone_int_decl("watchToPhoneValue", 3)
    }

    Process.put(:elmc_program_decls, decl_map)

    {code, out, _counter} =
      Host.compile_expr(companion_send_expr(), tail_env(decl_map), 0)

    refute code =~ "watchToPhoneTag(out,"
    refute code =~ "watchToPhoneValue(out,"
    assert code =~ "owned[0]"
    assert code =~ "owned[1]"
    assert code =~ "elmc_cmd2(ELMC_PEBBLE_CMD_COMPANION_SEND"
    assert out == "tmp_7"
  end
end
