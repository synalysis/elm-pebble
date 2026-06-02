defmodule ElmEx.DebuggerContract.ViewTree.Support do
  @moduledoc false

  alias ElmEx.DebuggerContract.Types
  alias ElmEx.DebuggerContract.ViewIntrinsics

  @spec first_non_nil([Types.wire_pick()]) :: Types.wire_pick()
  def first_non_nil(values) when is_list(values) do
    Enum.find(values, &(!is_nil(&1)))
  end

  @spec internal_arithmetic_view_type(String.t()) :: String.t()
  def internal_arithmetic_view_type(name) when is_binary(name) do
    if ViewIntrinsics.int_call_name?(name) or ViewIntrinsics.intrinsic_operator?(name),
      do: "call",
      else: name
  end

  @spec view_type_name(Types.ast_expr() | String.t()) :: String.t()
  def view_type_name(target) when is_binary(target) do
    case String.split(target, ".") |> List.last() do
      nil -> target
      last -> last
    end
  end

  @spec put_module_alias(
          %{optional(String.t()) => String.t()},
          String.t(),
          String.t()
        ) :: %{optional(String.t()) => String.t()}
  def put_module_alias(acc, alias_name, module_name)
      when is_map(acc) and is_binary(alias_name) and is_binary(module_name) and alias_name != "" do
    Map.put(acc, alias_name, module_name)
  end

  def put_module_alias(acc, _alias_name, _module_name) when is_map(acc), do: acc

  @spec module_short_name(String.t()) :: String.t()
  def module_short_name(module_name) when is_binary(module_name) do
    module_name |> String.split(".") |> List.last()
  end

  @spec view_arg_label(list()) :: String.t()
  def view_arg_label(args) when is_list(args) do
    prefix =
      args
      |> Enum.take(3)
      |> Enum.map(&view_arg_snippet/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join(", ")

    cond do
      prefix == "" -> ""
      length(args) > 3 -> prefix <> "…"
      true -> prefix
    end
  end

  @spec view_arg_snippet(Types.ast_expr()) :: String.t()
  def view_arg_snippet(%{op: :int_literal, value: v}), do: Integer.to_string(v)
  def view_arg_snippet(%{op: :float_literal, value: v}) when is_number(v), do: to_string(v)
  def view_arg_snippet(%{op: :char_literal, value: v}) when is_binary(v), do: inspect(v)
  def view_arg_snippet(%{op: :string_literal, value: v}), do: inspect(v)
  def view_arg_snippet(%{op: :var, name: n}), do: n
  def view_arg_snippet(%{op: :field_access} = expr), do: field_access_label(expr)
  def view_arg_snippet(%{op: :list_literal, items: is}), do: "[#{length(is)}]"
  def view_arg_snippet(_), do: "…"

  @spec field_access_label(Types.ast_expr()) :: String.t()
  def field_access_label(%{op: :field_access, arg: arg, field: field}) when is_binary(field) do
    case ElmEx.DebuggerContract.resolve_case_subject_expr(
           %{op: :field_access, arg: arg, field: field},
           %{}
         ) do
      value when is_binary(value) and value != "" -> value
      _ -> field
    end
  end

  def field_access_label(_), do: "field_access"
end
