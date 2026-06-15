defmodule Elmx.Backend.ElixirCodegen.Emit.Records do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit
  alias Elmx.Backend.ElixirCodegen.Emit.Helpers
  alias Elmx.Runtime.CodegenRefs

  @rt_values CodegenRefs.values()

  def compile_record(%{fields: fields}, env, counter) when is_list(fields) do
    {parts, {env, counter}} =
      Enum.map_reduce(Helpers.normalize_record_fields(fields), {env, counter}, fn {name, value}, {env, c} ->
        {code, env, c} = Helpers.compile_record_field_value(name, value, env, c)
        {[inspect(name), " => ", code], {env, c}}
      end)

    field_strs = Enum.map(parts, &IO.iodata_to_binary/1)
    {["%{", Enum.intersperse(field_strs, ", "), "}"], env, counter}
  end

  def compile_record_update(%{base: base, fields: fields}, env, counter) when is_list(fields) do
    {acc, env, counter} =
      Enum.reduce(fields, {nil, env, counter}, fn field, {acc, env, c} ->
        {name, value} = Helpers.record_update_field(field)
        {code, env, c} = Emit.compile_expr(value, env, c)

        next =
          if acc do
            ["Map.put(", acc, ", ", inspect(name), ", ", code, ")"]
          else
            {base_code, _env, _c} = Emit.compile_expr(base, env, c)
            ["Map.put(", base_code, ", ", inspect(name), ", ", code, ")"]
          end

        {next, env, c}
      end)

    {acc, env, counter}
  end

  def compile_record_update(%{base: base, field: field, value: value}, env, counter) do
    {base_code, env, c1} = Emit.compile_expr(base, env, counter)
    {value_code, env, c2} = Emit.compile_expr(value, env, c1)
    {["Map.put(", base_code, ", ", inspect(field), ", ", value_code, ")"], env, c2}
  end

  def compile_field_access(%{target: target, field: field}, env, counter) do
    {t, env, c1} = Emit.compile_expr(target, env, counter)
    {["Map.get(", t, ", ", inspect(field), ")"], env, c1}
  end

  def compile_field_access(%{record: record, field: field}, env, counter) do
    compile_field_access(%{target: record, field: field}, env, counter)
  end

  def compile_field_access(%{arg: arg, field: field}, env, counter) when is_binary(arg) do
    ref = Helpers.binding_ref(arg, env)
    {["Map.get(", ref, ", ", inspect(field), ")"], env, counter}
  end

  def compile_field_access(%{arg: arg, field: field}, env, counter) do
    compile_field_access(%{target: arg, field: field}, env, counter)
  end

  def compile_field_call(%{target: target, field: field, args: args}, env, counter) do
    {t, env, c1} = Emit.compile_expr(target, env, counter)
    {arg_code, env, c2} = Helpers.compile_arg_list(args, env, c1)
    {[@rt_values, ".field_call(", t, ", ", inspect(field), ", [", arg_code, "])"], env, c2}
  end

  def compile_field_call(%{arg: arg, field: field, args: args}, env, counter) do
    compile_field_call(%{target: arg, field: field, args: args}, env, counter)
  end

  def compile_field_call(%{record: record, field: field, args: args}, env, counter) do
    compile_field_call(%{target: record, field: field, args: args}, env, counter)
  end


end
