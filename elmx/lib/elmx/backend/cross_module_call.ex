defmodule Elmx.Backend.CrossModuleCall do
  @moduledoc false

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
        arity = cross_module_arity(env, module, name)

        code =
          cond do
            given == 0 and arity == 0 ->
              "#{fn_sym}()"

            given == 0 ->
              "&#{fn_sym}/#{max(arity, 1)}"

            given >= arity ->
              [fn_sym, "(", Enum.intersperse(arg_parts, ", "), ")"]

            true ->
              partial_application(fn_sym, arg_parts, max(arity - given, 1))
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
    env
    |> Map.get(:cross_module_arities, %{})
    |> Map.get({module, name}, 0)
  end

  defp partial_application(fn_sym, fixed_parts, 1) do
    ["&", fn_sym, "(", Enum.intersperse(fixed_parts, ", "), ", &1)"]
  end

  defp partial_application(fn_sym, fixed_parts, remaining) when remaining > 1 do
    param_names = Enum.map(1..remaining, &"__p#{&1}")
    all_args = fixed_parts ++ param_names
    inner = [fn_sym, "(", Enum.intersperse(all_args, ", "), ")"]

    Enum.reduce(Enum.reverse(param_names), inner, fn param, body ->
      ["fn ", param, " -> ", body, " end"]
    end)
  end

  defp safe_module(name), do: name |> String.replace(".", "_")
end
