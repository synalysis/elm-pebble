defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified.List do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib.QualifiedCodegen
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Context

  @type env :: Context.env()
  @type emit_counter :: Context.emit_counter()
  @type ir_arg_list :: Context.ir_arg_list()
  @type qualified_result :: Context.qualified_result()

  @spec compile(String.t(), ir_arg_list(), env(), emit_counter()) :: qualified_result()
  def compile("List.cons", [], env, counter) do
    {:ok, "&#{CodegenRefs.core()}.list_cons/2", env, counter}
  end

  def compile("List.foldl", [], env, counter) do
    {:ok, "&#{CodegenRefs.core()}.foldl/3", env, counter}
  end

  def compile("List.foldr", [], env, counter) do
    {:ok, "&#{CodegenRefs.core()}.foldr/3", env, counter}
  end

  def compile("List.filter", [pred, list], env, counter),
    do: compile_list_core_hof("filter", pred, list, env, counter)

  def compile("List.map", [fun], env, counter),
    do: compile_list_hof_partial("map", fun, env, counter)

  def compile("List.map", [fun, list], env, counter),
    do: compile_list_core_hof("map", fun, list, env, counter)

  def compile("List.filter", [pred], env, counter),
    do: compile_list_hof_partial("filter", pred, env, counter)

  def compile("List.filterMap", [fun], env, counter),
    do: compile_list_hof_partial("filter_map", fun, env, counter)

  def compile("List.filterMap", [fun, list], env, counter),
    do: compile_list_core_hof("filter_map", fun, list, env, counter)

  def compile("Elm.Kernel.List." <> rest, args, env, counter),
    do: compile("List." <> rest, args, env, counter)

  def compile("List.concat", [lists], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(lists, env, counter)
    {:ok, ["List.flatten(", code, ")"], env, c1}
  end

  def compile("List.concatMap", [fun], env, counter),
    do: compile_list_hof_partial("concat_map", fun, env, counter)

  def compile("List.concatMap", [fun, list], env, counter),
    do: compile_list_core_hof("concat_map", fun, list, env, counter)

  def compile("List.sortBy", [fun], env, counter),
    do: compile_list_hof_partial("sort_by", fun, env, counter)

  def compile("List.sortBy", [fun, list], env, counter),
    do: compile_list_core_hof("sort_by", fun, list, env, counter)

  def compile("List.sortWith", [fun], env, counter),
    do: compile_list_hof_partial("sort_with", fun, env, counter)

  def compile("List.sortWith", [fun, list], env, counter),
    do: compile_list_core_hof("sort_with", fun, list, env, counter)

  def compile("List.sum", [list], env, counter),
    do: compile_core_unary("list_sum", list, env, counter)

  def compile("List.product", [list], env, counter),
    do: compile_core_unary("list_product", list, env, counter)

  def compile("List.maximum", [list], env, counter),
    do: compile_core_unary("list_maximum", list, env, counter)

  def compile("List.minimum", [list], env, counter),
    do: compile_core_unary("list_minimum", list, env, counter)

  def compile("List.any", [fun], env, counter),
    do: compile_list_hof_partial("any", fun, env, counter)

  def compile("List.any", [fun, list], env, counter),
    do: compile_list_core_hof("any", fun, list, env, counter)

  def compile("List.all", [fun], env, counter),
    do: compile_list_hof_partial("all", fun, env, counter)

  def compile("List.all", [fun, list], env, counter),
    do: compile_list_core_hof("all", fun, list, env, counter)

  def compile("List.sort", [list], env, counter),
    do: compile_core_unary("sort", list, env, counter)

  def compile("List.head", [list], env, counter),
    do: compile_core_unary("list_head", list, env, counter)

  def compile("List.length", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["length(", list_code, ")"], env, c1}
  end

  def compile("List.range", [first, last], env, counter) do
    {a, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(first, env, counter)
    {b, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(last, env, c1)

    {:ok,
     [
       "Elmx.Runtime.Core.List.list_range(",
       a,
       ", ",
       b,
       ")"
     ], env, c2}
  end

  def compile("List.singleton", [value], env, counter) do
    {v, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, counter)
    {:ok, ["[", v, "]"], env, c1}
  end

  def compile("List.take", [n, list], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)
    {:ok, ["Enum.take(", list_code, ", ", n_code, ")"], env, c2}
  end

  def compile("List.drop", [n, list], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)
    {:ok, ["Enum.drop(", list_code, ", ", n_code, ")"], env, c2}
  end

  def compile("List.append", [left, right], env, counter) do
    {a, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(left, env, counter)
    {b, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(right, env, c1)
    {:ok, ["(", a, " ++ ", b, ")"], env, c2}
  end

  def compile("List.foldl", [fun], env, counter),
    do: compile_list_fold_partial("foldl", fun, env, counter, 2)

  def compile("List.foldl", [fun, acc], env, counter),
    do: compile_list_fold_partial("foldl", fun, acc, env, counter, 1)

  def compile("List.foldl", [fun, acc, list], env, counter) do
    compile_list_fold_core_hof("foldl", fun, acc, list, env, counter)
  end

  def compile("List.foldr", [fun], env, counter),
    do: compile_list_fold_partial("foldr", fun, env, counter, 2)

  def compile("List.foldr", [fun, acc], env, counter),
    do: compile_list_fold_partial("foldr", fun, acc, env, counter, 1)

  def compile("List.foldr", [fun, acc, list], env, counter) do
    compile_list_fold_core_hof("foldr", fun, acc, list, env, counter)
  end

  def compile("List.repeat", [n, value], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {v_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, c1)
    {:ok, code} = QualifiedCodegen.module_call(Elmx.Runtime.Core, "list_repeat", [n_code, v_code])
    {:ok, code, env, c2}
  end

  def compile("List.member", [value], env, counter) do
    {v_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, counter)
    list_param = Helpers.let_emit_name("__list")

    {:ok, code} =
      QualifiedCodegen.with_container(Elmx.Runtime.Core, "member", [v_code], nil,
        container_param: list_param
      )

    {:ok, code, env, c1}
  end

  def compile("List.member", [value, list], env, counter) do
    {v_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)

    {:ok, code} =
      QualifiedCodegen.with_container(Elmx.Runtime.Core, "member", [v_code], list_code,
        container_param: "elmx_list"
      )

    {:ok, code, env, c2}
  end

  def compile("List.reverse", [list], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, counter)
    {:ok, ["Enum.reverse(", list_code, ")"], env, c1}
  end

  def compile("List.tail", [list], env, counter),
    do: compile_core_unary("list_tail", list, env, counter)

  def compile("List.isEmpty", [list], env, counter),
    do: compile_core_unary("list_is_empty", list, env, counter)

  def compile("List.map2", [fun, as, bs], env, counter) do
    compile_core_nary("list_map2", [fun, as, bs], env, counter)
  end

  def compile("List.map3", [fun, as, bs, cs], env, counter) do
    compile_core_nary("list_map3", [fun, as, bs, cs], env, counter)
  end

  def compile("List.map4", [fun, as, bs, cs, ds], env, counter) do
    compile_core_nary("list_map4", [fun, as, bs, cs, ds], env, counter)
  end

  def compile("List.map5", [fun, as, bs, cs, ds, es], env, counter) do
    compile_core_nary("list_map5", [fun, as, bs, cs, ds, es], env, counter)
  end

  def compile("List.intersperse", [sep, list], env, counter) do
    compile_core_nary("list_intersperse", [sep, list], env, counter)
  end

  def compile("List.partition", [fun, list], env, counter) do
    compile_core_nary("list_partition", [fun, list], env, counter)
  end

  def compile("List.unzip", [list], env, counter),
    do: compile_core_unary("list_unzip", list, env, counter)

  def compile("List.indexedMap", [fun], env, counter) do
    {fun_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(fun, env, counter)
    {:ok, code} = QualifiedCodegen.list_hof("indexed_map", fun_code, nil)
    {:ok, code, env, c1}
  end

  def compile("List.indexedMap", [fun, list], env, counter) do
    {fun_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(fun, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)
    {:ok, code} = QualifiedCodegen.list_hof("indexed_map", fun_code, list_code)
    {:ok, code, env, c2}
  end

  def compile(_, _, _, _), do: :error

  defp compile_core_unary(fun, arg, env, counter) when is_binary(fun) do
    {arg_code, env, c} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(arg, env, counter)
    {:ok, code} = QualifiedCodegen.unary_call(Elmx.Runtime.Core, fun, arg_code)
    {:ok, code, env, c}
  end

  defp compile_core_nary(core_fun, args, env, counter) when is_binary(core_fun) and is_list(args) do
    {parts, env, c} = Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_parts(args, env, counter)
    {:ok, result} = QualifiedCodegen.module_call(Elmx.Runtime.Core, core_fun, parts)
    {:ok, result, env, c}
  end

  defp compile_list_core_hof(core_fun, fun, list, env, counter) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    {list_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c1)

    {:ok, code} = QualifiedCodegen.list_hof(core_fun, fun_code, list_code)
    {:ok, code, env, c2}
  end

  defp compile_list_hof_partial(core_fun, fun, env, counter) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    list_param = Helpers.let_emit_name("__list")
    {:ok, code} = QualifiedCodegen.list_hof(core_fun, fun_code, nil, list_param: list_param)
    {:ok, code, env, c1}
  end

  defp compile_list_fold_partial(core_fun, fun, env, counter, 2) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    acc_param = Helpers.let_emit_name("__acc")
    list_param = Helpers.let_emit_name("__list")

    {:ok, code} =
      QualifiedCodegen.list_fold(core_fun, fun_code, nil, nil,
        acc_param: acc_param,
        list_param: list_param
      )

    {:ok, code, env, c1}
  end

  defp compile_list_fold_partial(core_fun, fun, acc, env, counter, 1) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    {acc_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(acc, env, c1)
    list_param = Helpers.let_emit_name("__list")

    {:ok, code} =
      QualifiedCodegen.list_fold(core_fun, fun_code, acc_code, nil, list_param: list_param)

    {:ok, code, env, c2}
  end

  defp compile_list_fold_core_hof(core_fun, fun, acc, list, env, counter) do
    {fun_code, env, c1} = compile_fold_fun(fun, env, counter)
    {acc_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(acc, env, c1)
    {list_code, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(list, env, c2)
    {:ok, code} = QualifiedCodegen.list_fold(core_fun, fun_code, acc_code, list_code)
    {:ok, code, env, c3}
  end

  @comparison_ops ~w(__eq__ __neq__ __lt__ __lte__ __gt__ __gte__)

  defp compile_fold_fun(%{op: :qualified_call} = call, env, counter) do
    {code, env, c} = Elmx.Backend.ElixirCodegen.Emit.Qualified.compile_qualified_call(call, env, counter)
    {code, env, c}
  end

  defp compile_fold_fun(%{op: :var, name: name}, env, counter) when name in @comparison_ops do
    op = fold_operator_symbol(name)
    {["fn a, b -> a ", op, " b end"], env, counter}
  end

  defp compile_fold_fun(%{op: :var, name: "__add__"}, env, counter),
    do: {["fn a, b -> a + b end"], env, counter}

  defp compile_fold_fun(%{op: :var, name: "__mul__"}, env, counter),
    do: {["fn a, b -> a * b end"], env, counter}

  defp compile_fold_fun(%{op: :var, name: "__append__"}, env, counter),
    do: {["fn a, b -> ", CodegenRefs.core(), ".append(a, b) end"], env, counter}

  defp compile_fold_fun(%{op: :var, name: name}, env, counter) when is_binary(name) do
    module = Map.get(env, :module, "Main")
    {[Helpers.function_reference_uncurried(module, name, env)], env, counter}
  end

  defp compile_fold_fun(fun, env, counter),
    do: Elmx.Backend.ElixirCodegen.Emit.compile_expr(fun, env, counter)

  defp fold_operator_symbol("__eq__"), do: "=="
  defp fold_operator_symbol("__neq__"), do: "!="
  defp fold_operator_symbol("__lt__"), do: "<"
  defp fold_operator_symbol("__lte__"), do: "<="
  defp fold_operator_symbol("__gt__"), do: ">"
  defp fold_operator_symbol("__gte__"), do: ">="

end
