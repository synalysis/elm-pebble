defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified do
  @moduledoc false

  alias Elmx.Backend.CrossModuleCall
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Backend.QualifiedRewrite
  alias Elmx.Runtime.Pebble
  alias Elmx.Runtime.Pebble.SpecialValues
  alias Elmx.Runtime.Stdlib
  alias Elmx.Types

  @type env :: Types.emit_env()
  @type emit_counter :: Types.emit_counter()
  @type ir_arg_list :: Types.ir_arg_list()
  @type compile_expr_result :: Types.compile_expr_result()
  @type qualified_result :: {:ok, iodata(), env(), emit_counter()} | :error

  def compile_qualified_call1(%{target: target}, env, counter) when is_binary(target) do
    case Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_constructor_reference(target, env, counter) do
      {:ok, code, env, c} ->
        {code, env, c}

      :error ->
        case SpecialValues.rewrite(target, []) do
          {:ok, rewritten} ->
            Elmx.Backend.ElixirCodegen.Emit.compile_expr(rewritten, env, counter)

          :error ->
            case Stdlib.special_call(target, "") do
              {:ok, code} ->
                {code, env, counter}

              :error ->
                raise Elmx.Backend.UnsupportedOpError,
                  op: :qualified_call1,
                  expr: %{target: target}
            end
        end
    end
  end

  def compile_qualified_call(%{target: target, args: args}, env, counter) do
    case QualifiedRewrite.rewrite(target, args) do
      {:ok, rewritten} ->
        Elmx.Backend.ElixirCodegen.Emit.compile_expr(rewritten, env, counter)

      :error ->
        case Pebble.rewrite_qualified_call(target, args) do
          {:ok, rewritten} ->
            Elmx.Backend.ElixirCodegen.Emit.compile_expr(rewritten, env, counter)

          :error ->
            case compile_pebble_ui_qualified(target, args, env, counter) do
              {:ok, code, env, c} ->
                {code, env, c}

              :error ->
                case compile_list_qualified(target, args, env, counter) do
                  {:ok, code, env, c} ->
                    {code, env, c}

                  :error ->
                    case compile_string_qualified(target, args, env, counter) do
                      {:ok, code, env, c} ->
                        {code, env, c}

                      :error ->
                        case compile_collections_qualified(target, args, env, counter) do
                          {:ok, code, env, c} ->
                            {code, env, c}

                          :error ->
                            compile_qualified_call_fallback(target, args, env, counter)
                        end
                    end
                end
            end
        end
    end
  end

  def compile_pebble_ui_qualified(target, args, env, counter) do
    case {target, args} do
      {"Pebble.Ui.toUiNode", [ops]} ->
        pebble_ui_call(:to_ui_node, [ops], env, counter)

      {"Pebble.Ui.windowStack", [windows]} ->
        pebble_ui_call(:window_stack, [windows], env, counter)

      {"Pebble.Ui.window", [id, layers]} ->
        pebble_ui_call(:window, [id, layers], env, counter)

      {"Pebble.Ui.canvasLayer", [z, ops]} ->
        pebble_ui_call(:canvas_layer, [z, ops], env, counter)

      {"Pebble.Ui.group", [arg]} ->
        pebble_ui_call(:group, [arg], env, counter)

      {"Pebble.Ui.context", [settings, ops]} ->
        pebble_ui_call(:context, [settings, ops], env, counter)

      _ ->
        :error
    end
  end

  def pebble_ui_call(fun, args, env, counter) when is_atom(fun) and is_list(args) do
    {parts, env, c} = Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_parts(args, env, counter)

    {:ok,
     ["Elmx.Runtime.Pebble.Ui.", Atom.to_string(fun), "(", Enum.intersperse(parts, ", "), ")"],
     env, c}
  end

  def compile_list_qualified("List.filter", [pred, list], env, counter),
    do: compile_list_core_hof("filter", pred, list, env, counter)

  def compile_list_qualified("List.map", [fun], env, counter),
    do: compile_list_hof_partial("map", fun, env, counter)

  def compile_list_qualified("List.map", [fun, list], env, counter),
    do: compile_list_core_hof("map", fun, list, env, counter)

  def compile_list_qualified("List.filter", [pred], env, counter),
    do: compile_list_hof_partial("filter", pred, env, counter)

  def compile_list_qualified("List.filterMap", [fun], env, counter),
    do: compile_list_hof_partial("filter_map", fun, env, counter)

  def compile_list_qualified("List.filterMap", [fun, list], env, counter),
    do: compile_list_core_hof("filter_map", fun, list, env, counter)

  def compile_list_qualified("Elm.Kernel.List." <> rest, args, env, counter),
    do: compile_list_qualified("List." <> rest, args, env, counter)

  def compile_list_qualified("List.concat", [lists], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(lists, env, counter)
    {:ok, ["List.flatten(", code, ")"], env, c1}
  end

  def compile_list_qualified("List.concatMap", [fun], env, counter),
    do: compile_list_hof_partial("concat_map", fun, env, counter)

  def compile_list_qualified("List.concatMap", [fun, list], env, counter),
    do: compile_list_core_hof("concat_map", fun, list, env, counter)

  def compile_list_qualified("List.sortBy", [fun], env, counter),
    do: compile_list_hof_partial("sort_by", fun, env, counter)

  def compile_list_qualified("List.sortBy", [fun, list], env, counter),
    do: compile_list_core_hof("sort_by", fun, list, env, counter)

  def compile_list_qualified("List.sortWith", [fun], env, counter),
    do: compile_list_hof_partial("sort_with", fun, env, counter)

  def compile_list_qualified("List.sortWith", [fun, list], env, counter),
    do: compile_list_core_hof("sort_with", fun, list, env, counter)

  def compile_list_qualified("List.sum", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["Elmx.Runtime.Core.list_sum(", list_code, ")"], env, c1}
  end

  def compile_list_qualified("List.product", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["Elmx.Runtime.Core.list_product(", list_code, ")"], env, c1}
  end

  def compile_list_qualified("List.maximum", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["Elmx.Runtime.Core.list_maximum(", list_code, ")"], env, c1}
  end

  def compile_list_qualified("List.minimum", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["Elmx.Runtime.Core.list_minimum(", list_code, ")"], env, c1}
  end

  def compile_list_qualified("List.any", [fun], env, counter),
    do: compile_list_hof_partial("any", fun, env, counter)

  def compile_list_qualified("List.any", [fun, list], env, counter),
    do: compile_list_core_hof("any", fun, list, env, counter)

  def compile_list_qualified("List.all", [fun], env, counter),
    do: compile_list_hof_partial("all", fun, env, counter)

  def compile_list_qualified("List.all", [fun, list], env, counter),
    do: compile_list_core_hof("all", fun, list, env, counter)

  def compile_list_qualified("List.sort", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["Elmx.Runtime.Core.sort(", list_code, ")"], env, c1}
  end

  def compile_list_qualified("List.head", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["Elmx.Runtime.Core.list_head(", list_code, ")"], env, c1}
  end

  def compile_list_qualified("List.length", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["length(", list_code, ")"], env, c1}
  end

  def compile_list_qualified("List.range", [first, last], env, counter) do
    {a, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(first, env, counter)
    {b, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(last, env, c1)
    {:ok, ["Enum.to_list(", a, "..", b, ")"], env, c2}
  end

  def compile_list_qualified("List.singleton", [value], env, counter) do
    {v, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, counter)
    {:ok, ["[", v, "]"], env, c1}
  end

  def compile_list_qualified("List.take", [n, list], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)
    {:ok, ["Enum.take(", list_code, ", ", n_code, ")"], env, c2}
  end

  def compile_list_qualified("List.drop", [n, list], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)
    {:ok, ["Enum.drop(", list_code, ", ", n_code, ")"], env, c2}
  end

  def compile_list_qualified("List.append", [left, right], env, counter) do
    {a, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(left, env, counter)
    {b, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(right, env, c1)
    {:ok, ["(", a, " ++ ", b, ")"], env, c2}
  end

  def compile_list_qualified("List.foldl", [fun], env, counter),
    do: compile_list_fold_partial("foldl", fun, env, counter, 2)

  def compile_list_qualified("List.foldl", [fun, acc], env, counter),
    do: compile_list_fold_partial("foldl", fun, acc, env, counter, 1)

  def compile_list_qualified("List.foldl", [fun, acc, list], env, counter) do
    compile_list_fold_core_hof("foldl", fun, acc, list, env, counter)
  end

  def compile_list_qualified("List.foldr", [fun], env, counter),
    do: compile_list_fold_partial("foldr", fun, env, counter, 2)

  def compile_list_qualified("List.foldr", [fun, acc], env, counter),
    do: compile_list_fold_partial("foldr", fun, acc, env, counter, 1)

  def compile_list_qualified("List.foldr", [fun, acc, list], env, counter) do
    compile_list_fold_core_hof("foldr", fun, acc, list, env, counter)
  end

  def compile_list_qualified("List.repeat", [n, value], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {v_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, c1)
    {:ok, ["Elmx.Runtime.Core.list_repeat(", n_code, ", ", v_code, ")"], env, c2}
  end

  def compile_list_qualified("List.member", [value], env, counter) do
    {v_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, counter)
    list = Helpers.let_emit_name("__list")

    {:ok,
     ["fn ", list, " -> Elmx.Runtime.Core.member(", v_code, ", ", list, ") end"],
     env, c1}
  end

  def compile_list_qualified("List.member", [value, list], env, counter) do
    {v_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)
    {:ok, ["Elmx.Runtime.Core.member(", v_code, ", ", list_code, ")"], env, c2}
  end

  def compile_list_qualified("List.reverse", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["Enum.reverse(", list_code, ")"], env, c1}
  end

  def compile_list_qualified("List.indexedMap", [fun], env, counter) do
    {fun_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(fun, env, counter)
    list = Helpers.let_emit_name("__list")
    {:ok, ["fn ", list, " -> Elmx.Runtime.Core.indexed_map(", fun_code, ", ", list, ") end"], env, c1}
  end

  def compile_list_qualified("List.indexedMap", [fun, list], env, counter) do
    {fun_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(fun, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)

    {:ok,
     ["Elmx.Runtime.Core.indexed_map(", fun_code, ", ", list_code, ")"],
     env, c2}
  end

  def compile_list_qualified(_, _, _, _), do: :error

  defp compile_list_core_hof(core_fun, fun, list, env, counter) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)

    {:ok,
     ["Elmx.Runtime.Core.", core_fun, "(", fun_code, ", ", list_code, ")"],
     env, c2}
  end

  defp compile_list_hof_partial(core_fun, fun, env, counter) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    list = Helpers.let_emit_name("__list")

    {:ok,
     ["fn ", list, " -> Elmx.Runtime.Core.", core_fun, "(", fun_code, ", ", list, ") end"],
     env, c1}
  end

  defp compile_list_fold_partial(core_fun, fun, env, counter, 2) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    acc = Helpers.let_emit_name("__acc")
    list = Helpers.let_emit_name("__list")

    {:ok,
     [
       "fn ",
       acc,
       ", ",
       list,
       " -> Elmx.Runtime.Core.",
       core_fun,
       "(",
       fun_code,
       ", ",
       acc,
       ", ",
       list,
       ") end"
     ], env, c1}
  end

  defp compile_list_fold_partial(core_fun, fun, acc, env, counter, 1) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    {acc_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(acc, env, c1)
    list = Helpers.let_emit_name("__list")

    {:ok,
     [
       "fn ",
       list,
       " -> Elmx.Runtime.Core.",
       core_fun,
       "(",
       fun_code,
       ", ",
       acc_code,
       ", ",
       list,
       ") end"
     ], env, c2}
  end

  defp compile_list_fold_core_hof(core_fun, fun, acc, list, env, counter) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    {acc_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(acc, env, c1)
    {list_code, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c2)

    {:ok,
     ["Elmx.Runtime.Core.", core_fun, "(", fun_code, ", ", acc_code, ", ", list_code, ")"],
     env, c3}
  end

  @comparison_ops ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__)

  defp compile_fold_fun(%{op: :var, name: name}, env, counter) when name in @comparison_ops do
    op = fold_operator_symbol(name)
    {["fn a, b -> a ", op, " b end"], env, counter}
  end

  defp compile_fold_fun(%{op: :var, name: "__add__"}, env, counter),
    do: {["fn a, b -> a + b end"], env, counter}

  defp compile_fold_fun(%{op: :var, name: "__mul__"}, env, counter),
    do: {["fn a, b -> a * b end"], env, counter}

  defp compile_fold_fun(%{op: :var, name: "__append__"}, env, counter),
    do: {["fn a, b -> Elmx.Runtime.Core.append(a, b) end"], env, counter}

  defp compile_fold_fun(fun, env, counter),
    do: Elmx.Backend.ElixirCodegen.Emit.compile_expr(fun, env, counter)

  defp fold_operator_symbol("__eq__"), do: "=="
  defp fold_operator_symbol("__neq__"), do: "!="
  defp fold_operator_symbol("__lt__"), do: "<"
  defp fold_operator_symbol("__lte__"), do: "<="
  defp fold_operator_symbol("__gt__"), do: ">"
  defp fold_operator_symbol("__gte__"), do: ">="

  def compile_string_qualified("String.isEmpty", [value], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, counter)
    {:ok, ["(", code, " == \"\")"], env, c1}
  end

  def compile_string_qualified("String.left", [n, str], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {s_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, c1)
    {:ok, ["String.slice(", s_code, ", 0, ", n_code, ")"], env, c2}
  end

  def compile_string_qualified("String.right", [n, str], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {s_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, c1)
    {:ok, ["String.slice(", s_code, ", max(0, String.length(", s_code, ") - ", n_code, "), ", n_code, ")"], env, c2}
  end

  def compile_string_qualified("String.dropLeft", [n, str], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {s_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, c1)
    {:ok, ["String.slice(", s_code, ", ", n_code, ", String.length(", s_code, "))"], env, c2}
  end

  def compile_string_qualified("String.dropRight", [n, str], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {s_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, c1)
    {:ok, ["String.slice(", s_code, ", 0, max(0, String.length(", s_code, ") - ", n_code, "))"], env, c2}
  end

  def compile_string_qualified("String.toUpper", [str], env, counter) do
    {s_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, counter)
    {:ok, ["String.upcase(", s_code, ")"], env, c1}
  end

  def compile_string_qualified("String.toLower", [str], env, counter) do
    {s_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, counter)
    {:ok, ["String.downcase(", s_code, ")"], env, c1}
  end

  def compile_string_qualified("String.trim", [str], env, counter) do
    {s_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, counter)
    {:ok, ["String.trim(", s_code, ")"], env, c1}
  end

  def compile_string_qualified("String.trimLeft", [str], env, counter),
    do: compile_string_unary("trim_left", str, env, counter)

  def compile_string_qualified("String.trimRight", [str], env, counter),
    do: compile_string_unary("trim_right", str, env, counter)

  def compile_string_qualified("String.length", [str], env, counter),
    do: compile_string_unary("length_val", str, env, counter)

  def compile_string_qualified("String.reverse", [str], env, counter),
    do: compile_string_unary("reverse", str, env, counter)

  def compile_string_qualified("String.words", [str], env, counter),
    do: compile_string_unary("words", str, env, counter)

  def compile_string_qualified("String.lines", [str], env, counter),
    do: compile_string_unary("lines", str, env, counter)

  def compile_string_qualified("String.toInt", [str], env, counter),
    do: compile_string_unary("to_int", str, env, counter)

  def compile_string_qualified("String.toFloat", [str], env, counter),
    do: compile_string_unary("to_float", str, env, counter)

  def compile_string_qualified("String.fromFloat", [arg], env, counter),
    do: compile_string_unary("from_float", arg, env, counter)

  def compile_string_qualified("String.slice", [start, len, text], env, counter) do
    {s, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(start, env, counter)
    {l, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(len, env, c1)
    {t, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c2)

    {:ok, ["Elmx.Runtime.Core.Strings.slice(", s, ", ", l, ", ", t, ")"], env, c3}
  end

  def compile_string_qualified("String.padLeft", [n, ch, text], env, counter),
    do: compile_string_pad("pad_left", n, ch, text, env, counter)

  def compile_string_qualified("String.padRight", [n, ch, text], env, counter),
    do: compile_string_pad("pad_right", n, ch, text, env, counter)

  def compile_string_qualified("String.pad", [n, ch, text], env, counter),
    do: compile_string_pad("pad", n, ch, text, env, counter)

  def compile_string_qualified("String.cons", [head, tail], env, counter),
    do: compile_string_binary("cons", head, tail, env, counter)

  def compile_string_qualified("String.cons", [head], env, counter),
    do: compile_string_binary_partial("cons", head, env, counter)

  def compile_string_qualified("String.uncons", [str], env, counter),
    do: compile_string_unary("uncons", str, env, counter)

  def compile_string_qualified("String.toList", [str], env, counter),
    do: compile_string_unary("to_list", str, env, counter)

  def compile_string_qualified("String.fromList", [list], env, counter),
    do: compile_string_unary("from_list", list, env, counter)

  def compile_string_qualified("String.fromChar", [ch], env, counter),
    do: compile_string_unary("from_char", ch, env, counter)

  def compile_string_qualified("String.fromInt", [arg], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(arg, env, counter)
    {:ok, ["Integer.to_string(", code, ")"], env, c1}
  end

  def compile_string_qualified("String.split", [sep], env, counter) do
    {sep_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(sep, env, counter)
    str = Helpers.let_emit_name("__str")

    {:ok,
     ["fn ", str, " -> Elmx.Runtime.Core.Strings.split(", sep_code, ", ", str, ") end"],
     env, c1}
  end

  def compile_string_qualified("String.split", [sep, text], env, counter) do
    {sep_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(sep, env, counter)
    {text_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c1)

    {:ok,
     ["Elmx.Runtime.Core.Strings.split(", sep_code, ", ", text_code, ")"],
     env, c2}
  end

  def compile_string_qualified("String.join", [sep], env, counter) do
    {sep_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(sep, env, counter)
    list = Helpers.let_emit_name("__list")

    {:ok,
     ["fn ", list, " -> Elmx.Runtime.Core.Strings.join(", sep_code, ", ", list, ") end"],
     env, c1}
  end

  def compile_string_qualified("String.join", [sep, list], env, counter) do
    {sep_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(sep, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)

    {:ok,
     ["Elmx.Runtime.Core.Strings.join(", sep_code, ", ", list_code, ")"],
     env, c2}
  end

  def compile_string_qualified("String.contains", [sub], env, counter) do
    compile_string_binary_partial("contains", sub, env, counter)
  end

  def compile_string_qualified("String.contains", [sub, text], env, counter) do
    compile_string_binary("contains", sub, text, env, counter)
  end

  def compile_string_qualified("String.startsWith", [prefix], env, counter) do
    compile_string_binary_partial("starts_with", prefix, env, counter)
  end

  def compile_string_qualified("String.startsWith", [prefix, text], env, counter) do
    compile_string_binary("starts_with", prefix, text, env, counter)
  end

  def compile_string_qualified("String.endsWith", [suffix], env, counter) do
    compile_string_binary_partial("ends_with", suffix, env, counter)
  end

  def compile_string_qualified("String.endsWith", [suffix, text], env, counter) do
    compile_string_binary("ends_with", suffix, text, env, counter)
  end

  def compile_string_qualified("String.repeat", [n], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    str = Helpers.let_emit_name("__str")

    {:ok,
     ["fn ", str, " -> Elmx.Runtime.Core.Strings.repeat(", n_code, ", ", str, ") end"],
     env, c1}
  end

  def compile_string_qualified("String.repeat", [n, text], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {text_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c1)

    {:ok,
     ["Elmx.Runtime.Core.Strings.repeat(", n_code, ", ", text_code, ")"],
     env, c2}
  end

  def compile_string_qualified("String.replace", [before, after_str], env, counter) do
    {before_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(before, env, counter)
    {after_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(after_str, env, c1)
    str = Helpers.let_emit_name("__str")

    {:ok,
     [
       "fn ",
       str,
       " -> Elmx.Runtime.Core.Strings.replace(",
       before_code,
       ", ",
       after_code,
       ", ",
       str,
       ") end"
     ], env, c2}
  end

  def compile_string_qualified("String.replace", [before, after_str, text], env, counter) do
    {before_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(before, env, counter)
    {after_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(after_str, env, c1)
    {text_code, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c2)

    {:ok,
     [
       "Elmx.Runtime.Core.Strings.replace(",
       before_code,
       ", ",
       after_code,
       ", ",
       text_code,
       ")"
     ], env, c3}
  end

  def compile_string_qualified("Elm.Kernel.String." <> rest, args, env, counter),
    do: compile_string_qualified("String." <> rest, args, env, counter)

  def compile_string_qualified(_, _, _, _), do: :error

  defp compile_string_binary(fun, fixed, text, env, counter) do
    {fixed_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(fixed, env, counter)
    {text_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c1)

    {:ok,
     ["Elmx.Runtime.Core.Strings.", fun, "(", fixed_code, ", ", text_code, ")"],
     env, c2}
  end

  defp compile_string_binary_partial(fun, fixed, env, counter) do
    {fixed_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(fixed, env, counter)
    str = Helpers.let_emit_name("__str")

    {:ok,
     [
       "fn ",
       str,
       " -> Elmx.Runtime.Core.Strings.",
       fun,
       "(",
       fixed_code,
       ", ",
       str,
       ") end"
     ], env, c1}
  end

  defp compile_string_unary(fun, str, env, counter) do
    {str_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, counter)

    {:ok,
     ["Elmx.Runtime.Core.Strings.", fun, "(", str_code, ")"],
     env, c1}
  end

  defp compile_string_pad(fun, n, ch, text, env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {ch_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(ch, env, c1)
    {text_code, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c2)

    {:ok,
     ["Elmx.Runtime.Core.Strings.", fun, "(", n_code, ", ", ch_code, ", ", text_code, ")"],
     env, c3}
  end

  def compile_collections_qualified("Dict.get", [key, dict], env, counter),
    do: compile_collections_binary("Collections.dict_get", key, dict, env, counter)

  def compile_collections_qualified("Dict.get", [key], env, counter),
    do: compile_collections_binary_partial("Collections.dict_get", key, env, counter)

  def compile_collections_qualified("Dict.insert", [key, value, dict], env, counter),
    do: compile_collections_ternary("Collections.dict_insert", key, value, dict, env, counter)

  def compile_collections_qualified("Dict.insert", [key, value], env, counter),
    do: compile_collections_ternary_partial("Collections.dict_insert", key, value, env, counter)

  def compile_collections_qualified("Dict.remove", [key, dict], env, counter),
    do: compile_collections_binary("Collections.dict_remove", key, dict, env, counter)

  def compile_collections_qualified("Dict.remove", [key], env, counter),
    do: compile_collections_binary_partial("Collections.dict_remove", key, env, counter)

  def compile_collections_qualified("Dict.member", [key, dict], env, counter),
    do: compile_collections_binary("Collections.dict_member", key, dict, env, counter)

  def compile_collections_qualified("Dict.member", [key], env, counter),
    do: compile_collections_binary_partial("Collections.dict_member", key, env, counter)

  def compile_collections_qualified("Set.member", [value, set], env, counter),
    do: compile_collections_binary("Collections.set_member", value, set, env, counter)

  def compile_collections_qualified("Set.member", [value], env, counter),
    do: compile_collections_binary_partial("Collections.set_member", value, env, counter, "elmx_set")

  def compile_collections_qualified("Array.get", [index, array], env, counter),
    do: compile_collections_binary("Collections.array_get", index, array, env, counter)

  def compile_collections_qualified("Array.get", [index], env, counter),
    do: compile_collections_binary_partial("Collections.array_get", index, env, counter, "elmx_array")

  def compile_collections_qualified(_, _, _, _), do: :error

  defp compile_collections_binary(mod_fun, a, b, env, counter) do
    {a_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(a, env, counter)
    {b_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(b, env, c1)

    {:ok, ["Elmx.Runtime.Core.", mod_fun, "(", a_code, ", ", b_code, ")"], env, c2}
  end

  defp compile_collections_binary_partial(mod_fun, a, env, counter, dict \\ "elmx_dict") do
    {a_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(a, env, counter)
    param = Helpers.let_emit_name(dict)

    {:ok,
     ["fn ", param, " -> Elmx.Runtime.Core.", mod_fun, "(", a_code, ", ", param, ") end"],
     env, c1}
  end

  defp compile_collections_ternary(mod_fun, a, b, c, env, counter) do
    {a_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(a, env, counter)
    {b_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(b, env, c1)
    {c_code, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(c, env, c2)

    {:ok,
     ["Elmx.Runtime.Core.", mod_fun, "(", a_code, ", ", b_code, ", ", c_code, ")"],
     env, c3}
  end

  defp compile_collections_ternary_partial(mod_fun, a, b, env, counter) do
    {a_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(a, env, counter)
    {b_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(b, env, c1)
    dict = Helpers.let_emit_name("elmx_dict")

    {:ok,
     [
       "fn ",
       dict,
       " -> Elmx.Runtime.Core.",
       mod_fun,
       "(",
       a_code,
       ", ",
       b_code,
       ", ",
       dict,
       ") end"
     ], env, c2}
  end

  @spec compile_qualified_call_fallback(String.t(), ir_arg_list(), env(), emit_counter()) ::
          compile_expr_result()
  def compile_qualified_call_fallback(target, args, env, counter) do
    case compile_basics_qualified(target, args, env, counter) do
      {:ok, code, env, c} ->
        {code, env, c}

      :error ->
        case compile_bitwise_qualified(target, args, env, counter) do
          {:ok, code, env, c} ->
            {code, env, c}

          :error ->
            compile_qualified_call_fallback_string(target, args, env, counter)
        end
    end
  end

  @spec compile_basics_qualified(String.t(), ir_arg_list(), env(), emit_counter()) ::
          qualified_result()
  def compile_basics_qualified("Basics." <> op, [left, right], env, counter)
      when op in ["min", "max"] do
    {l, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(left, env, counter)
    {r, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(right, env, c1)
    {:ok, [op, "(", l, ", ", r, ")"], env, c2}
  end

  def compile_basics_qualified("Basics.abs", [arg], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(arg, env, counter)
    {:ok, ["abs(", code, ")"], env, c1}
  end

  def compile_basics_qualified("Basics.negate", [arg], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(arg, env, counter)
    {:ok, ["-(", code, ")"], env, c1}
  end

  def compile_basics_qualified("Basics.not", [arg], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(arg, env, counter)
    {:ok, ["not ", code], env, c1}
  end

  def compile_basics_qualified("Basics.modBy", [divisor, value], env, counter) do
    {d, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(divisor, env, counter)
    {v, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, c1)
    {:ok, ["Integer.mod(", v, ", ", d, ")"], env, c2}
  end

  def compile_basics_qualified("Basics.remainderBy", [divisor, value], env, counter) do
    {d, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(divisor, env, counter)
    {v, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, c1)
    {:ok, ["rem(", v, ", ", d, ")"], env, c2}
  end

  def compile_basics_qualified("Basics.compare", [left, right], env, counter) do
    {l, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(left, env, counter)
    {r, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(right, env, c1)
    {:ok, ["Elmx.Runtime.Core.basics_compare(", l, ", ", r, ")"], env, c2}
  end

  def compile_basics_qualified("Basics.clamp", [lo, hi, value], env, counter) do
    {lo_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(lo, env, counter)
    {hi_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(hi, env, c1)
    {val_code, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, c2)

    {:ok,
     ["Elmx.Runtime.Core.basics_clamp(", lo_code, ", ", hi_code, ", ", val_code, ")"],
     env, c3}
  end

  def compile_basics_qualified("String.fromInt", [arg], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(arg, env, counter)
    {:ok, ["Integer.to_string(", code, ")"], env, c1}
  end

  def compile_basics_qualified(_, _, _, _), do: :error

  @spec compile_bitwise_qualified(String.t(), ir_arg_list(), env(), emit_counter()) ::
          qualified_result()
  def compile_bitwise_qualified("Bitwise.and", [left, right], env, counter) do
    compile_bitwise_runtime(:and_, [left, right], env, counter)
  end

  def compile_bitwise_qualified("Bitwise.or", [left, right], env, counter) do
    compile_bitwise_runtime(:or_, [left, right], env, counter)
  end

  def compile_bitwise_qualified("Bitwise.xor", [left, right], env, counter) do
    compile_bitwise_runtime(:xor, [left, right], env, counter)
  end

  def compile_bitwise_qualified("Bitwise.complement", [arg], env, counter) do
    compile_bitwise_runtime(:complement, [arg], env, counter)
  end

  def compile_bitwise_qualified("Bitwise.shiftLeftBy", [bits, arg], env, counter) do
    compile_bitwise_runtime(:shift_left_by, [bits, arg], env, counter)
  end

  def compile_bitwise_qualified("Bitwise.shiftRightBy", [bits, arg], env, counter) do
    compile_bitwise_runtime(:shift_right_by, [bits, arg], env, counter)
  end

  def compile_bitwise_qualified("Bitwise.shiftRightZfBy", [bits, arg], env, counter) do
    compile_bitwise_runtime(:shift_right_zf_by, [bits, arg], env, counter)
  end

  def compile_bitwise_qualified(_, _, _, _), do: :error

  defp compile_bitwise_runtime(fun, args, env, counter) when is_atom(fun) and is_list(args) do
    {parts, env, c} = Helpers.compile_arg_parts(args, env, counter)

    {:ok,
     [
       "Elmx.Runtime.Core.Bitwise.",
       Atom.to_string(fun),
       "(",
       Enum.intersperse(parts, ", "),
       ")"
     ], env, c}
  end

  @spec compile_qualified_call_fallback_string(String.t(), ir_arg_list(), env(), emit_counter()) ::
          compile_expr_result()
  def compile_qualified_call_fallback_string(target, args, env, counter) do
    {arg_code, env, c1} =
      Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_list(args, env, counter)

    arg_str = IO.iodata_to_binary(arg_code)

    case Elmx.Runtime.Stdlib.qualified_call(target, arg_str) do
      {:ok, code} ->
        {code, env, c1}

      :error ->
        case CrossModuleCall.compile_call(target, args, env, counter, &Helpers.compile_arg_parts/3) do
          {:ok, code, env, c2} ->
            {code, env, c2}

          :error ->
            if String.contains?(target, ".") do
              raise Elmx.Backend.UnsupportedOpError,
                op: :qualified_call,
                expr: %{target: target, args: args}
            else
              fn_name = Helpers.qualified_fn_name(target)
              module = Map.get(env, :module, "Main")
              {[Helpers.module_fn(module, fn_name), "(", arg_str, ")"], env, c1}
            end
        end
    end
  end
end
