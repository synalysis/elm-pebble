defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified.String do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Runtime.Stdlib.QualifiedCodegen
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Context

  @type env :: Context.env()
  @type emit_counter :: Context.emit_counter()
  @type ir_arg_list :: Context.ir_arg_list()
  @type qualified_result :: Context.qualified_result()

  def compile("String.isEmpty", [value], env, counter) do
    {code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(value, env, counter)
    {:ok, ["(", code, " == \"\")"], env, c1}
  end

  def compile("String.left", [n, str], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {s_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, c1)
    {:ok, ["String.slice(", s_code, ", 0, ", n_code, ")"], env, c2}
  end

  def compile("String.right", [n, str], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {s_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, c1)
    {:ok, ["String.slice(", s_code, ", max(0, String.length(", s_code, ") - ", n_code, "), ", n_code, ")"], env, c2}
  end

  def compile("String.dropLeft", [n, str], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {s_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, c1)
    {:ok, ["String.slice(", s_code, ", ", n_code, ", String.length(", s_code, "))"], env, c2}
  end

  def compile("String.dropRight", [n, str], env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {s_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, c1)
    {:ok, ["String.slice(", s_code, ", 0, max(0, String.length(", s_code, ") - ", n_code, "))"], env, c2}
  end

  def compile("String.toUpper", [str], env, counter) do
    {s_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, counter)
    {:ok, ["String.upcase(", s_code, ")"], env, c1}
  end

  def compile("String.toLower", [str], env, counter) do
    {s_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, counter)
    {:ok, ["String.downcase(", s_code, ")"], env, c1}
  end

  def compile("String.trim", [str], env, counter) do
    {s_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, counter)
    {:ok, ["String.trim(", s_code, ")"], env, c1}
  end

  def compile("String.trimLeft", [str], env, counter),
    do: compile_string_unary("trim_left", str, env, counter)

  def compile("String.trimRight", [str], env, counter),
    do: compile_string_unary("trim_right", str, env, counter)

  def compile("String.length", [str], env, counter),
    do: compile_string_unary("length_val", str, env, counter)

  def compile("String.reverse", [str], env, counter),
    do: compile_string_unary("reverse", str, env, counter)

  def compile("String.words", [str], env, counter),
    do: compile_string_unary("words", str, env, counter)

  def compile("String.lines", [str], env, counter),
    do: compile_string_unary("lines", str, env, counter)

  def compile("String.toInt", [str], env, counter),
    do: compile_string_unary("to_int", str, env, counter)

  def compile("String.toFloat", [str], env, counter),
    do: compile_string_unary("to_float", str, env, counter)

  def compile("String.fromFloat", [arg], env, counter),
    do: compile_string_unary("from_float", arg, env, counter)

  def compile("String.slice", [start, len, text], env, counter) do
    {s, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(start, env, counter)
    {l, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(len, env, c1)
    {t, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c2)

    {:ok, code} = QualifiedCodegen.with_container(Elmx.Runtime.Core.Strings, "slice", [s, l], t)
    {:ok, code, env, c3}
  end

  def compile("String.padLeft", [n, ch, text], env, counter),
    do: compile_string_pad("pad_left", n, ch, text, env, counter)

  def compile("String.padRight", [n, ch, text], env, counter),
    do: compile_string_pad("pad_right", n, ch, text, env, counter)

  def compile("String.pad", [n, ch, text], env, counter),
    do: compile_string_pad("pad", n, ch, text, env, counter)

  def compile("String.cons", [head, tail], env, counter),
    do: compile_string_binary("cons", head, tail, env, counter)

  def compile("String.cons", [head], env, counter),
    do: compile_string_binary_partial("cons", head, env, counter)

  def compile("String.uncons", [str], env, counter),
    do: compile_string_unary("uncons", str, env, counter)

  def compile("String.toList", [str], env, counter),
    do: compile_string_unary("to_list", str, env, counter)

  def compile("String.fromList", [list], env, counter),
    do: compile_string_unary("from_list", list, env, counter)

  def compile("String.fromChar", [ch], env, counter),
    do: compile_string_unary("from_char", ch, env, counter)

  def compile("String.fromInt", [arg], env, counter),
    do: Elmx.Backend.ElixirCodegen.Emit.Qualified.compile_stdlib_qualified_ir("String.fromInt", [arg], env, counter)

  def compile("String.split", [sep], env, counter),
    do: compile_string_binary_partial("split", sep, env, counter)

  def compile("String.split", [sep, text], env, counter),
    do: compile_string_binary("split", sep, text, env, counter)

  def compile("String.join", [sep], env, counter),
    do: compile_string_binary_partial("join", sep, env, counter, "elmx_list")

  def compile("String.join", [sep, list], env, counter),
    do: compile_string_binary("join", sep, list, env, counter)

  def compile("String.concat", [strings], env, counter) do
    {list_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(strings, env, counter)
    {:ok, ["Enum.join(", list_code, ", \"\")"], env, c1}
  end

  def compile("String.contains", [sub], env, counter) do
    compile_string_binary_partial("contains", sub, env, counter)
  end

  def compile("String.contains", [sub, text], env, counter) do
    compile_string_binary("contains", sub, text, env, counter)
  end

  def compile("String.startsWith", [prefix], env, counter) do
    compile_string_binary_partial("starts_with", prefix, env, counter)
  end

  def compile("String.startsWith", [prefix, text], env, counter) do
    compile_string_binary("starts_with", prefix, text, env, counter)
  end

  def compile("String.endsWith", [suffix], env, counter) do
    compile_string_binary_partial("ends_with", suffix, env, counter)
  end

  def compile("String.endsWith", [suffix, text], env, counter) do
    compile_string_binary("ends_with", suffix, text, env, counter)
  end

  def compile("String.repeat", [n], env, counter),
    do: compile_string_binary_partial("repeat", n, env, counter)

  def compile("String.repeat", [n, text], env, counter),
    do: compile_string_binary("repeat", n, text, env, counter)

  def compile("String.replace", [before, after_str], env, counter),
    do: compile_string_ternary_partial("replace", before, after_str, env, counter)

  def compile("String.replace", [before, after_str, text], env, counter) do
    {before_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(before, env, counter)
    {after_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(after_str, env, c1)
    {text_code, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c2)

    {:ok, code} =
      QualifiedCodegen.with_container(Elmx.Runtime.Core.Strings, "replace", [before_code, after_code], text_code)

    {:ok, code, env, c3}
  end

  def compile("String.map", [fun, text], env, counter),
    do: compile_strings_hof("map", fun, text, env, counter)

  def compile("String.filter", [fun, text], env, counter),
    do: compile_strings_hof("filter", fun, text, env, counter)

  def compile("String.foldl", [fun, acc, text], env, counter),
    do: compile_strings_fold("foldl", fun, acc, text, env, counter)

  def compile("String.foldr", [fun, acc, text], env, counter),
    do: compile_strings_fold("foldr", fun, acc, text, env, counter)

  def compile("String.all", [fun, text], env, counter),
    do: compile_strings_hof("all", fun, text, env, counter)

  def compile("String.any", [fun, text], env, counter),
    do: compile_strings_hof("any", fun, text, env, counter)

  def compile("String.indexes", [substr, text], env, counter),
    do: compile_strings_hof("indexes", substr, text, env, counter)

  def compile("String.indices", [substr, text], env, counter),
    do: compile_strings_hof("indexes", substr, text, env, counter)

  def compile("Elm.Kernel.String." <> rest, args, env, counter),
    do: compile("String." <> rest, args, env, counter)

  def compile(_, _, _, _), do: :error

  defp compile_strings_hof(fun, f, text, env, counter) do
    {f_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(f, env, counter)
    {t_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c1)

    {:ok, code} =
      QualifiedCodegen.with_container(Elmx.Runtime.Core.Strings, fun, [f_code], t_code,
        container_param: "elmx_text"
      )

    {:ok, code, env, c2}
  end

  defp compile_strings_fold(fun, f, acc, text, env, counter) do
    {f_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(f, env, counter)
    {acc_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(acc, env, c1)
    {t_code, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c2)

    {:ok, code} =
      QualifiedCodegen.list_fold(fun, f_code, acc_code, t_code,
        module: Elmx.Runtime.Core.Strings,
        list_param: "elmx_text"
      )

    {:ok, code, env, c3}
  end

  defp compile_string_binary(fun, fixed, text, env, counter) do
    {fixed_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(fixed, env, counter)
    {text_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c1)

    {:ok, code} =
      QualifiedCodegen.with_container(Elmx.Runtime.Core.Strings, fun, [fixed_code], text_code)

    {:ok, code, env, c2}
  end

  defp compile_string_binary_partial(fun, fixed, env, counter, container \\ "elmx_str") do
    {fixed_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(fixed, env, counter)
    param = Helpers.let_emit_name(container)

    {:ok, code} =
      QualifiedCodegen.with_container(Elmx.Runtime.Core.Strings, fun, [fixed_code], nil,
        container_param: param
      )

    {:ok, code, env, c1}
  end

  defp compile_string_ternary_partial(fun, a, b, env, counter, container \\ "elmx_str") do
    {a_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(a, env, counter)
    {b_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(b, env, c1)
    param = Helpers.let_emit_name(container)

    {:ok, code} =
      QualifiedCodegen.with_container(Elmx.Runtime.Core.Strings, fun, [a_code, b_code], nil,
        container_param: param
      )

    {:ok, code, env, c2}
  end

  defp compile_string_unary(fun, str, env, counter) do
    {str_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(str, env, counter)
    {:ok, code} = QualifiedCodegen.unary_call(Elmx.Runtime.Core.Strings, fun, str_code)
    {:ok, code, env, c1}
  end

  defp compile_string_pad(fun, n, ch, text, env, counter) do
    {n_code, env, c1} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(n, env, counter)
    {ch_code, env, c2} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(ch, env, c1)
    {text_code, env, c3} = Elmx.Backend.ElixirCodegen.Emit.compile_expr(text, env, c2)

    {:ok, code} =
      QualifiedCodegen.with_container(Elmx.Runtime.Core.Strings, fun, [n_code, ch_code], text_code)

    {:ok, code, env, c3}
  end

end
