defmodule Elmx.Backend.CrossModuleCall do
  @moduledoc false

  alias Elmx.Backend.ElixirCodegen.Emit.Helpers

  @spec split_target(String.t()) :: {String.t(), String.t()} | nil
  def split_target(target) when is_binary(target) do
    case String.split(target, ".") do
      [_] ->
        nil

      parts ->
        name = List.last(parts)
        module = parts |> Enum.drop(-1) |> Enum.join(".")
        {module, name}
    end
  end

  @spec function_symbol(String.t(), String.t()) :: String.t()
  def function_symbol(module, name) when is_binary(module) and is_binary(name) do
    "elmx_fn_#{safe_module(module)}_#{name}"
  end

  @spec compile_call(String.t(), list(), map(), non_neg_integer(), function()) ::
          {:ok, iodata(), map(), non_neg_integer()} | :error
  def compile_call(target, args, env, counter, compile_arg_parts)
      when is_binary(target) and is_function(compile_arg_parts, 3) do
    case split_target(target) do
      {module, name} ->
        unless cross_module_allowed?(env, module) do
          :error
        else
          compile_cross_module_call(module, name, args, env, counter, compile_arg_parts)
        end

      nil ->
        :error
    end
  end

  defp compile_cross_module_call(module, name, args, env, counter, compile_arg_parts) do
        {arg_parts, env, c1} = compile_arg_parts.(args, env, counter)
        fn_sym = function_symbol(module, name)
        given = length(args)
        %{explicit: explicit, callable: callable} = cross_module_arity(env, module, name)

        code =
          cond do
            Map.get(env, :emit_partial_value) == true and given < explicit ->
              [fn_sym, "(", Enum.intersperse(arg_parts, ", "), ")"]

            given == 0 and explicit == 0 and callable == 0 ->
              "#{fn_sym}()"

            given == 0 ->
              "&#{fn_sym}/#{max(callable, 1)}"

            given > explicit ->
              if explicit == 0 and given == callable do
                [fn_sym, "(", Enum.intersperse(arg_parts, ", "), ")"]
              else
                {fixed, extra} = Enum.split(arg_parts, explicit)

                base =
                  if fixed == [] do
                    "&#{fn_sym}/#{max(callable, 1)}"
                  else
                    [fn_sym, "(", Enum.intersperse(fixed, ", "), ")"]
                  end

                Enum.reduce(extra, base, fn arg, acc ->
                  ["Elmx.Runtime.Core.Apply.apply1(", acc, ", ", arg, ")"]
                end)
              end

            given == explicit ->
              [fn_sym, "(", Enum.intersperse(arg_parts, ", "), ")"]

            true ->
              partial_application(fn_sym, arg_parts, max(explicit - given, 1))
          end

        {:ok, code, env, c1}
  end

  defp cross_module_allowed?(env, module) do
    case Map.get(env, :emit_module_names) do
      names when is_list(names) -> module in names
      _ -> false
    end
  end

  defp cross_module_arity(env, module, name) do
    Map.get(Map.get(env, :cross_module_arities, %{}), {module, name}, %{explicit: 0, callable: 0})
  end

  defp partial_application(fn_sym, fixed_parts, 1) do
    param = Helpers.let_emit_name("__p1")

    [
      "fn ",
      param,
      " -> ",
      fn_sym,
      "(",
      Enum.intersperse(fixed_parts ++ [param], ", "),
      ")",
      " end"
    ]
  end

  defp partial_application(fn_sym, fixed_parts, remaining) when remaining > 1 do
    param_names = Enum.map(1..remaining, &Helpers.let_emit_name("__p#{&1}"))
    all_args = fixed_parts ++ param_names
    inner = [fn_sym, "(", Enum.intersperse(all_args, ", "), ")"]

    Enum.reduce(Enum.reverse(param_names), inner, fn param, body ->
      ["fn ", param, " -> ", body, " end"]
    end)
  end

  defp safe_module(name), do: name |> String.replace(".", "_")
end
