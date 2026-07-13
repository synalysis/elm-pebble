defmodule Elmc.Backend.Plan.ThinDelegate do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Host
  alias Elmc.Backend.Plan.Types

  @kernel_call_names ~w(
    modBy
    __add__
    __sub__
    __mul__
    __div__
    __neg__
    __eq__
    __lt__
    __le__
    __gt__
    __ge__
  )

  @spec thin_delegate?(Types.function_decl(), String.t(), Types.function_decl_map()) :: boolean()
  def thin_delegate?(decl, module_name, decl_map) when is_map(decl) do
    case Host.function_return_type(Map.get(decl, :type)) do
      ret when ret in ["Int", "Bool"] ->
        thin_delegate_expr?(Map.get(decl, :expr), module_name, decl_map)

      _ ->
        false
    end
  end

  def thin_delegate?(_, _, _), do: false

  @spec thin_delegate_expr?(Types.ir_expr() | nil, String.t(), Types.function_decl_map()) :: boolean()
  def thin_delegate_expr?(expr, module_name, decl_map) do
    case expr do
      %{op: :qualified_call, target: target, args: args} when is_list(args) ->
        case parse_qualified_target(target) do
          {mod, name} -> user_callee?(mod, name, decl_map)
          :error -> false
        end

      %{op: :call, name: name, args: args} when is_binary(name) and is_list(args) ->
        user_callee?(module_name, name, decl_map) and not kernel_call?(name)

      _ ->
        false
    end
  end

  defp user_callee?(module, name, decl_map),
    do: is_map(Map.get(decl_map, {module, name}))

  defp kernel_call?(name) when is_binary(name),
    do: name in @kernel_call_names or String.starts_with?(name, "__")

  defp parse_qualified_target(target) when is_binary(target) do
    case String.split(target, ".") do
      [mod, name] when mod != "" and name != "" -> {mod, name}
      _ -> :error
    end
  end

  defp parse_qualified_target(_), do: :error
end
