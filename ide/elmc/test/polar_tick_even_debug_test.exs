defmodule Elmc.PolarTickEvenDebugTest do
  use ExUnit.Case, async: false

  alias Elmc.Backend.CCodegen.DirectRender.ListLoopPlans
  alias Elmc.Backend.CCodegen.IRQueries
  alias Elmc.TestSupport.TemplateCompile

  test "watchface even tick label IR is polar-fusable" do
    {:ok, result} =
      TemplateCompile.compile_watch_template("watchface_yes",
        direct_render_only: true,
        prune_runtime: true,
        pebble_int32: true,
        strip_dead_code: true
      )

    decl_map = IRQueries.function_decl_map(result.ir)
    draw_outer = Map.fetch!(decl_map, {"Yes.Render", "drawOuterScale"})

    env =
      %{
        __module__: "Yes.Render",
        __program_decls__: decl_map,
        __record_alias_shapes__: IRQueries.record_alias_shape_map(result.ir)
      }
      |> then(&fragment_env(draw_outer.expr, &1))

    list = outer_concat_list(draw_outer.expr)
    assert {:ok, [_odd, even]} = ListLoopPlans.analyze(list, env)

    %{map: %{param: param, body: body}} = even
    fields = field_map(body)

    case ListLoopPlans.polar_tick_fusion_debug(
           even,
           {"Yes.Render", "drawScaleTick"},
           ["layout"],
           env
         ) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        flunk("""
        even tick fusion failed: #{inspect(reason)}
        param=#{inspect(param)}
        minute=#{inspect(fields["minute"], limit: 30)}
        outerExtra=#{inspect(fields["outerExtra"], limit: 10)}
        label=#{inspect(fields["label"], limit: 30)}
        """)
    end
  end

  defp fragment_env(expr, env) do
    lets(expr)
    |> Enum.reduce(env, fn {name, value}, acc ->
      Map.put(acc, name, {:direct_fragment, value})
    end)
  end

  defp lets(%{op: :let_in, name: name, value_expr: value, in_expr: in_expr}) do
    [{name, value} | lets(in_expr)]
  end

  defp lets(_), do: []

  defp outer_concat_list(%{op: :qualified_call, target: "List.concatMap", args: [_fun, list]}), do: list

  defp outer_concat_list(%{op: :call, name: "__append__", args: [left, right]}) do
    outer_concat_list(left) || outer_concat_list(right)
  end

  defp outer_concat_list(%{op: :let_in, in_expr: in_expr}), do: outer_concat_list(in_expr)

  defp outer_concat_list(_), do: nil

  defp field_map(%{op: :record_literal, fields: fields}) when is_list(fields) do
    Map.new(fields, fn
      %{name: name, expr: expr} when is_atom(name) -> {Atom.to_string(name), expr}
      %{name: name, expr: expr} -> {name, expr}
    end)
  end
end
