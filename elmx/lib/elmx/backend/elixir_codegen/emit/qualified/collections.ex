defmodule Elmx.Backend.ElixirCodegen.Emit.Qualified.Collections do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Runtime.CodegenRefs
  alias Elmx.Runtime.Stdlib.QualifiedCodegen
  alias Elmx.Backend.ElixirCodegen.Emit.Qualified.Context

  @type env :: Context.env()
  @type emit_counter :: Context.emit_counter()
  @type ir_arg_list :: Context.ir_arg_list()
  @type qualified_result :: Context.qualified_result()

  def compile("Dict.get", [key, dict], env, counter),
    do: compile_collections_op("dict", "get", [key], dict, env, counter)

  def compile("Dict.get", [key], env, counter),
    do: compile_collections_op("dict", "get", [key], nil, env, counter)

  def compile("Dict.insert", [key, value, dict], env, counter),
    do: compile_collections_op("dict", "insert", [key, value], dict, env, counter)

  def compile("Dict.insert", [key, value], env, counter),
    do: compile_collections_op("dict", "insert", [key, value], nil, env, counter)

  def compile("Dict.remove", [key, dict], env, counter),
    do: compile_collections_op("dict", "remove", [key], dict, env, counter)

  def compile("Dict.remove", [key], env, counter),
    do: compile_collections_op("dict", "remove", [key], nil, env, counter)

  def compile("Dict.member", [key, dict], env, counter),
    do: compile_collections_op("dict", "member", [key], dict, env, counter)

  def compile("Dict.member", [key], env, counter),
    do: compile_collections_op("dict", "member", [key], nil, env, counter)

  def compile("Set.member", [value, set], env, counter),
    do: compile_collections_op("set", "member", [value], set, env, counter, "elmx_set")

  def compile("Set.member", [value], env, counter),
    do: compile_collections_op("set", "member", [value], nil, env, counter, "elmx_set")

  def compile("Set.insert", [], env, counter) do
    {:ok, "&#{CodegenRefs.core_collections()}.set_insert/2", env, counter}
  end

  def compile("Set.insert", [value], env, counter),
    do: compile_collections_op("set", "insert", [value], nil, env, counter, "elmx_set")

  def compile("Set.insert", [value, set], env, counter),
    do: compile_collections_op("set", "insert", [value], set, env, counter, "elmx_set")

  def compile("Set.empty", [], env, counter) do
    {:ok, "#{CodegenRefs.core_collections()}.set_empty()", env, counter}
  end

  def compile("Dict.empty", [], env, counter) do
    {:ok, "#{CodegenRefs.core_collections()}.dict_empty()", env, counter}
  end

  def compile("Set.remove", [], env, counter) do
    {:ok, "&#{CodegenRefs.core_collections()}.set_remove/2", env, counter}
  end

  def compile("Set.remove", [value], env, counter),
    do: compile_collections_op("set", "remove", [value], nil, env, counter, "elmx_set")

  def compile("Set.remove", [value, set], env, counter),
    do: compile_collections_op("set", "remove", [value], set, env, counter, "elmx_set")

  def compile("Array.get", [index, array], env, counter),
    do: compile_collections_op("array", "get", [index], array, env, counter, "elmx_array")

  def compile("Array.get", [index], env, counter),
    do: compile_collections_op("array", "get", [index], nil, env, counter, "elmx_array")

  def compile(_, _, _, _), do: :error

  defp compile_collections_op(prefix, op, prefix_args, container, env, counter, container_label \\ "elmx_dict") do
    {prefix_codes, env, c} =
      Elmx.Backend.ElixirCodegen.Emit.Helpers.compile_arg_parts(prefix_args, env, counter)

    fun = collection_fun_name(prefix, op)

    case container do
      nil ->
        param = Helpers.let_emit_name(container_label)

        {:ok, code} =
          QualifiedCodegen.with_container(Elmx.Runtime.Core.Collections, fun, prefix_codes, nil,
            container_param: param
          )

        {:ok, code, env, c}

      container_expr ->
        {container_code, env, c2} =
          Elmx.Backend.ElixirCodegen.Emit.compile_expr(container_expr, env, c)

        {:ok, code} =
          QualifiedCodegen.with_container(Elmx.Runtime.Core.Collections, fun, prefix_codes, container_code)

        {:ok, code, env, c2}
    end
  end

  defp collection_fun_name(prefix, op) when is_binary(prefix) and is_binary(op),
    do: prefix <> "_" <> Macro.underscore(op)


end
