defmodule Elmx.Runtime.Stdlib.Qualified.Helpers do
  @moduledoc false

  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib.QualifiedCodegen
  alias Elmx.Types

  @type qualified_arg_code :: Types.qualified_arg_code()
  @type qualified_call_result :: Types.qualified_call_result()

  def list_core_hof(core_fun, arg_code) do
    case split_args(arg_code) do
      [fun_expr, list] -> QualifiedCodegen.list_hof(core_fun, fun_expr, list)
      [fun_expr] -> QualifiedCodegen.list_hof(core_fun, fun_expr, nil)
      _ -> :error
    end
  end

  def list_core_fold(core_fun, arg_code) do
    case split_args(arg_code) do
      [fun_expr, acc, list] -> QualifiedCodegen.list_fold(core_fun, fun_expr, acc, list)
      [fun_expr, acc] -> QualifiedCodegen.list_fold(core_fun, fun_expr, acc, nil)
      [fun_expr] -> QualifiedCodegen.list_fold(core_fun, fun_expr, nil, nil)
      _ -> :error
    end
  end

  def list_repeat(arg_code) do
    case split_args(arg_code) do
      [n, value] -> QualifiedCodegen.module_call(Elmx.Runtime.Core, "list_repeat", [n, value])
      _ -> :error
    end
  end

  def core_unary(fun, arg_code) when is_binary(fun) do
    case split_args(arg_code) do
      [arg] -> QualifiedCodegen.unary_call(Elmx.Runtime.Core, fun, arg)
      [] -> QualifiedCodegen.unary_call(Elmx.Runtime.Core, fun, nil)
      _ -> :error
    end
  end

  def list_member(arg_code) do
    case split_args(arg_code) do
      [value, list] ->
        QualifiedCodegen.with_container(Elmx.Runtime.Core, "member", [value], list,
          container_param: "elmx_list"
        )

      [value] ->
        QualifiedCodegen.with_container(Elmx.Runtime.Core, "member", [value], nil,
          container_param: "elmx_list"
        )

      _ ->
        :error
    end
  end

  def dict_get(arg_code) do
    container_dict(arg_code, "dict_get", 2)
  end

  def dict_insert(arg_code) do
    container_dict(arg_code, "dict_insert", 3)
  end

  def dict_remove(arg_code) do
    container_dict(arg_code, "dict_remove", 2)
  end

  def dict_member(arg_code) do
    container_dict(arg_code, "dict_member", 2)
  end

  def set_insert(arg_code) do
    container_set(arg_code, "set_insert", 2)
  end

  def set_remove(arg_code) do
    container_set(arg_code, "set_remove", 2)
  end

  def set_member(arg_code) do
    container_set(arg_code, "set_member", 2)
  end

  def container_dict(arg_code, fun, arity) do
    mod = CodegenRefs.core_collections()

    case {arity, split_args(arg_code)} do
      {2, [a, b]} -> QualifiedCodegen.with_container(mod, fun, [a], b)
      {2, [a]} -> QualifiedCodegen.with_container(mod, fun, [a], nil)
      {3, [a, b, c]} -> QualifiedCodegen.with_container(mod, fun, [a, b], c)
      {3, [a, b]} -> QualifiedCodegen.with_container(mod, fun, [a, b], nil)
      _ -> :error
    end
  end

  def container_set(arg_code, fun, arity) do
    mod = CodegenRefs.core_collections()

    case {arity, split_args(arg_code)} do
      {2, [a, b]} -> QualifiedCodegen.with_container(mod, fun, [a], b, container_param: "elmx_set")
      {2, [a]} -> QualifiedCodegen.with_container(mod, fun, [a], nil, container_param: "elmx_set")
      _ -> :error
    end
  end

  def unary(op, arg_code), do: {:ok, "(#{op}(#{pick(arg_code, 0)}))"}

  def binary_fn(op, arg_code) do
    case split_args(arg_code) do
      [left, right] -> {:ok, "#{op}(#{left}, #{right})"}
      _ -> :error
    end
  end

  def string_replace(arg_code), do: strings_container(arg_code, "replace", 3)
  def string_split(arg_code), do: strings_container(arg_code, "split", 2)
  def string_join(arg_code), do: strings_container(arg_code, "join", 2, "elmx_list")
  def string_binary(fun, arg_code), do: strings_container(arg_code, fun, 2)
  def string_repeat(arg_code), do: strings_container(arg_code, "repeat", 2)

  def string_unary(fun, arg_code) do
    case split_args(arg_code) do
      [text] -> QualifiedCodegen.unary_call(Elmx.Runtime.Core.Strings, fun, text)
      [] -> QualifiedCodegen.unary_call(Elmx.Runtime.Core.Strings, fun, nil)
      _ -> :error
    end
  end

  def string_slice(arg_code) do
    case split_args(arg_code) do
      [start, len, text] ->
        QualifiedCodegen.with_container(Elmx.Runtime.Core.Strings, "slice", [start, len], text)

      _ ->
        :error
    end
  end

  def string_pad(fun, arg_code) do
    case split_args(arg_code) do
      [n, ch, text] ->
        QualifiedCodegen.with_container(Elmx.Runtime.Core.Strings, fun, [n, ch], text)

      _ ->
        :error
    end
  end

  def strings_container(arg_code, fun, arity, container_param \\ "elmx_str") do
    mod = CodegenRefs.core_strings()

    case {arity, split_args(arg_code)} do
      {2, [a, b]} -> QualifiedCodegen.with_container(mod, fun, [a], b, container_param: container_param)
      {2, [a]} -> QualifiedCodegen.with_container(mod, fun, [a], nil, container_param: container_param)
      {3, [a, b, c]} -> QualifiedCodegen.with_container(mod, fun, [a, b], c, container_param: container_param)
      {3, [a, b]} -> QualifiedCodegen.with_container(mod, fun, [a, b], nil, container_param: container_param)
      _ -> :error
    end
  end

  def json_decode_binary(fun, arg_code) do
    case split_args(arg_code) do
      [a, b] ->
        QualifiedCodegen.with_container(Elmx.Runtime.Json.Decode, fun, [a], b,
          container_param: "elmx_dec"
        )

      [a] ->
        QualifiedCodegen.with_container(Elmx.Runtime.Json.Decode, fun, [a], nil,
          container_param: "elmx_dec"
        )

      _ ->
        :error
    end
  end

  def json_decode_unary_builder(fun, arg_code) do
    case split_args(arg_code) do
      [inner] -> QualifiedCodegen.unary_call(Elmx.Runtime.Json.Decode, fun, inner, param: "elmx_inner")
      [] -> QualifiedCodegen.unary_call(Elmx.Runtime.Json.Decode, fun, nil, param: "elmx_inner")
      _ -> :error
    end
  end

  def json_map_n(mod, fun, arg_code, count) when is_atom(mod) and is_binary(fun) and is_integer(count) do
    case split_args(arg_code) do
      args when length(args) == count -> QualifiedCodegen.module_call(mod, fun, args)
      _ -> :error
    end
  end

  def mod_by(arg_code) do
    case split_args(arg_code) do
      [divisor, value] -> {:ok, "Integer.mod(#{value}, #{divisor})"}
      _ -> :error
    end
  end

  def remainder_by(arg_code) do
    case split_args(arg_code) do
      [divisor, value] -> {:ok, "rem(#{value}, #{divisor})"}
      _ -> :error
    end
  end

  def maybe_with_default(arg_code) do
    case split_args(arg_code) do
      [default, maybe] ->
        QualifiedCodegen.module_call(Elmx.Runtime.Core.MaybeResult, "maybe_with_default", [default, maybe])

      _ ->
        :error
    end
  end

  def maybe_map(arg_code), do: combinator_from_args(arg_code, "maybe_map")
  def maybe_and_then(arg_code), do: combinator_from_args(arg_code, "maybe_and_then")

  def basics_negate(arg_code) do
    case split_args(arg_code) do
      [arg] -> {:ok, "(-(#{arg}))"}
      _ -> :error
    end
  end

  def string_to_int(arg_code) do
    arg = pick(arg_code, 0)

    {:ok,
     "(case Integer.parse(#{arg}) do {n, _} -> n; :error -> 0 end)"}
  end

  def string_to_float(arg_code) do
    arg = pick(arg_code, 0)

    {:ok,
     "(case Float.parse(#{arg}) do {f, _} -> f; :error -> 0.0 end)"}
  end

  def result_map_error(arg_code) do
    combinator_from_args(arg_code, "result_map_error")
  end

  def result_and_then(arg_code) do
    combinator_from_args(arg_code, "result_and_then")
  end

  def combinator_from_args(arg_code, fun) do
    case split_args(arg_code) do
      [f] -> QualifiedCodegen.combinator_last(Elmx.Runtime.Core.MaybeResult, fun, [f], nil)
      [f, r] -> QualifiedCodegen.combinator_last(Elmx.Runtime.Core.MaybeResult, fun, [f], r)
      _ -> :error
    end
  end

  def runtime_unary(mod, fun, arg_code) when is_atom(mod) and is_binary(fun) do
    case split_args(arg_code) do
      [arg] -> QualifiedCodegen.unary_call(mod, fun, arg)
      [] -> QualifiedCodegen.unary_call(mod, fun, nil)
      _ -> :error
    end
  end

  def wrapped_runtime_unary(mod, fun, arg_code) when is_atom(mod) and is_binary(fun) do
    case runtime_unary(mod, fun, arg_code) do
      {:ok, code} -> {:ok, "(#{code})"}
      :error -> :error
    end
  end

  def runtime_binary(mod, fun, arg_code) when is_atom(mod) and is_binary(fun) do
    case split_args(arg_code) do
      [a, b] -> QualifiedCodegen.module_call(mod, fun, [a, b])
      _ -> :error
    end
  end

  def runtime_ternary(mod, fun, arg_code) when is_atom(mod) and is_binary(fun) do
    case split_args(arg_code) do
      [a, b, c] -> QualifiedCodegen.module_call(mod, fun, [a, b, c])
      _ -> :error
    end
  end

  def runtime_nary(mod, fun, arg_code, count) when is_atom(mod) and is_binary(fun) and is_integer(count) do
    case split_args(arg_code) do
      args when length(args) == count -> QualifiedCodegen.module_call(mod, fun, args)
      _ -> :error
    end
  end

  def pick(arg_code, index), do: Enum.at(split_args(arg_code), index) || "0"

  def split_args(arg_code) when is_binary(arg_code) do
    Elmx.Runtime.Stdlib.split_top_level_args(arg_code)
  end

end
