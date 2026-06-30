defmodule Elmc.BoxedStringAppendRcTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.RcRuntimeEmit
  alias Elmc.Backend.CCodegen.ValueSlots

  test "boxed fromInt ++ literal branch appends via elmc_string_append into out" do
    ValueSlots.reset(epilogue_lifo: true)

    append_expr = %{
      op: :runtime_call,
      function: "elmc_append",
      args: [
        %{
          op: :runtime_call,
          function: "elmc_string_from_int",
          args: [%{op: :var, name: "tuple_speed"}]
        },
        %{op: :string_literal, value: "m/s"}
      ]
    }

    out = RcRuntimeEmit.function_out_ref()

    env =
      %{
        "tuple_speed" => "((ElmcTuple2 *)speed->payload)->second",
        "speed" => "speed"
      }
      |> Map.put(:__rc_catch__, true)
      |> Map.put(:__rc_required__, true)
      |> Map.put(:__branch_out__, out)
      |> Map.put(:__declared_outs__, MapSet.new([out]))

    {code, assignment, _counter} =
      CaseCompile.branch_assignment(append_expr, out, env, 0)

    body = code <> assignment

    assert body =~
             ~r/snprintf\(native_string_buf_\d+, sizeof\(native_string_buf_\d+\), "%lldm\/s", \(long long\)elmc_as_int\(owned\[0\]\)\);\s+Rc = elmc_new_string\(out, native_string_buf_\d+\)/
    refute body =~ "elmc_string_append(out,"
    refute body =~ "elmc_append("
    refute body =~ ~r/\*out = owned\[\d+\];/
    refute body =~ ~r/elmc_new_string\(&tmp_\d+,/
  end
end
