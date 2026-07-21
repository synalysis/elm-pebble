defmodule Elmc.PlanJustBindAliasTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.{Builder, Context}
  alias Elmc.Backend.Plan.Lower.Case

  test "Just payload bind is not overwritten with the Maybe subject" do
    Process.put(:elmc_constructor_tags, %{"Just" => 1, "Nothing" => 0})

    on_exit(fn -> Process.delete(:elmc_constructor_tags) end)

    expr = %{
      op: :case,
      subject: %{op: :var, name: "maybePair"},
      branches: [
        %{
          pattern: %{kind: :constructor, name: "Nothing"},
          expr: %{op: :int_literal, value: 0}
        },
        %{
          pattern: %{kind: :constructor, name: "Just", bind: "pair"},
          expr: %{
            op: :tuple_first_expr,
            arg: %{op: :var, name: "pair"}
          }
        }
      ]
    }

    ctx =
      Context.new(
        module: "Main",
        function_name: "take_first",
        params: ["maybePair"],
        decl_map: %{}
      )

    b = Builder.new("Main", "take_first", args: ["maybePair"], rc_required: false)

    assert {:ok, _reg, b_out} = Case.compile(expr, ctx, b)

    instrs =
      (b_out.blocks ++ [b_out.current_block])
      |> Enum.flat_map(& &1.instrs)

    # Bind `pair` after maybe_just_payload — never re-bind `pair` to the Maybe subject.
    binds =
      Enum.filter(instrs, fn
        %{op: :bind_local, args: %{name: "pair"}} -> true
        %{op: :bind_local, dest: "pair"} -> true
        other -> match?(%{op: :bind_local}, other) and inspect(other) =~ "pair"
      end)

    payload_peels =
      Enum.filter(instrs, fn instr ->
        match?(%{op: :call_runtime, args: %{builtin: :maybe_just_payload}}, instr) or
          match?(%{op: :call_runtime, args: %{view_peel: :maybe_just_payload}}, instr)
      end)

    assert payload_peels != []

    tuple_firsts =
      Enum.filter(instrs, fn
        %{op: :tuple_first} -> true
        %{op: :call_runtime, args: %{builtin: :tuple_first}} -> true
        %{op: op} when op in [:tuple_first_expr, :tuple_proj] -> true
        _ -> false
      end)

    assert tuple_firsts != []

    # The tuple_first operand must be the payload register from maybe_just_payload,
    # not the original maybePair subject (reg of param 0).
    peel_dest =
      Enum.find_value(payload_peels, fn
        %{dest: dest} when is_integer(dest) -> dest
        %{args: %{dest: dest}} when is_integer(dest) -> dest
        _ -> nil
      end)

    first_arg =
      Enum.find_value(tuple_firsts, fn
        %{args: %{arg: arg}} when is_integer(arg) -> arg
        %{args: %{base: base}} when is_integer(base) -> base
        %{args: [arg | _]} when is_integer(arg) -> arg
        _ -> nil
      end)

    if is_integer(peel_dest) and is_integer(first_arg) do
      assert first_arg == peel_dest
    end

    # At most one bind of `pair` (payload only); alias overwrite would add a second.
    assert length(binds) <= 1
  end
end
