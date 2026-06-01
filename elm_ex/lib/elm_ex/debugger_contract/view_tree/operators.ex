defmodule ElmEx.DebuggerContract.ViewTree.Operators do
  @moduledoc false

  alias ElmEx.DebuggerContract.ViewTree
  alias ElmEx.DebuggerContract.ViewTree.Structure
  alias ElmEx.DebuggerContract.ViewTree.Support
  alias ElmEx.DebuggerContract.Types

  @spec from_view_expr(Types.ast_expr() | nil, Types.view_build_metadata()) :: Types.view_tree()
  def from_view_expr(nil, _api_metadata), do: ViewTree.view_tree_unknown()

  def from_view_expr(expr, api_metadata) when is_map(api_metadata) do
    expr
    |> normalize_view_expr()
    |> build_view_tree(api_metadata)
    |> ViewTree.annotate_view_tree_sources(api_metadata)
  end

  @spec unknown() :: Types.view_tree()
  def unknown, do: ViewTree.view_tree_unknown()

  @spec build_view_tree(Types.ast_expr(), Types.view_build_metadata()) :: Types.view_tree()
  def build_view_tree(expr, api_metadata) when is_map(api_metadata) do
    expr_to_view_tree(expr, 0, 40, api_metadata)
  end

  @spec expr_to_view_tree(
          Types.ast_expr() | nil,
          non_neg_integer(),
          non_neg_integer(),
          Types.view_build_metadata()
        ) :: Types.view_tree()
  def expr_to_view_tree(nil, _, _, _api_metadata), do: ViewTree.view_tree_unknown()

  def expr_to_view_tree(%{op: :expr, expr: inner}, d, max, api_metadata) when d < max do
    expr_to_view_tree(inner, d, max, api_metadata)
  end

  def expr_to_view_tree(%{op: :expr, value_expr: inner}, d, max, api_metadata) when d < max do
    expr_to_view_tree(inner, d, max, api_metadata)
  end

  def expr_to_view_tree(%{op: :expr, in_expr: inner}, d, max, api_metadata) when d < max do
    expr_to_view_tree(inner, d, max, api_metadata)
  end

  def expr_to_view_tree(%{op: op} = expr, d, max, api_metadata)
       when d < max and (op == :list_literal or op == "list_literal") do
    items =
      Support.first_non_nil([
        Map.get(expr, :items),
        Map.get(expr, "items"),
        Map.get(expr, :elements),
        Map.get(expr, "elements"),
        []
      ])

    list_items = if is_list(items), do: items, else: []

    %{
      "type" => "List",
      "label" => Integer.to_string(length(list_items)),
      "children" => Enum.map(list_items, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
  end

  def expr_to_view_tree(%{op: :tuple2, left: left, right: right}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "expr",
      "label" => "tuple2",
      "children" => [
        expr_to_view_tree(left, d + 1, max, api_metadata),
        expr_to_view_tree(right, d + 1, max, api_metadata)
      ],
      "op" => "tuple2"
    }
  end

  def expr_to_view_tree(%{op: :qualified_call, target: t, args: args}, d, max, api_metadata)
       when d < max do
    arity = length(args)

    %{
      "type" => Support.view_type_name(t),
      "qualified_target" => t,
      "label" => Support.view_arg_label(args),
      "arg_names" => Structure.source_call_arg_names(t, arity, api_metadata),
      "children" => Enum.map(args, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
    |> Structure.maybe_put_view_tree_return_kind(t, arity, api_metadata)
  end

  def expr_to_view_tree(%{op: :constructor_call, target: t, args: args}, d, max, api_metadata)
       when d < max do
    arity = length(args)

    %{
      "type" => Support.view_type_name(t),
      "qualified_target" => t,
      "label" => Support.view_arg_label(args),
      "arg_names" => Structure.source_call_arg_names(t, arity, api_metadata),
      "children" => Enum.map(args, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
    |> Structure.maybe_put_view_tree_return_kind(t, arity, api_metadata)
  end

  def expr_to_view_tree(%{op: :call, name: name, args: args}, d, max, api_metadata)
       when d < max do
    arity = length(args)
    target = Structure.view_tree_call_target_name(name, api_metadata)

    %{
      "type" => Support.internal_arithmetic_view_type(name),
      "qualified_target" => target,
      "label" => name,
      "arg_names" => Structure.source_call_arg_names(target, arity, api_metadata),
      "children" => Enum.map(args, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
    |> Structure.maybe_put_view_tree_return_kind(target, arity, api_metadata)
  end

  def expr_to_view_tree(%{op: :lambda, body: body}, d, max, api_metadata) when d < max do
    expr_to_view_tree(body, d + 1, max, api_metadata)
  end

  def expr_to_view_tree(%{op: :let_in, name: name, value_expr: value, in_expr: inner}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "let",
      "label" => to_string(name),
      "children" => [
        expr_to_view_tree(value, d + 1, max, api_metadata),
        expr_to_view_tree(inner, d + 1, max, api_metadata)
      ]
    }
  end

  def expr_to_view_tree(%{op: :if, cond: cond, then_expr: t, else_expr: e}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "if",
      "label" => "",
      "children" => [
        expr_to_view_tree(cond, d + 1, max, api_metadata),
        expr_to_view_tree(t, d + 1, max, api_metadata),
        expr_to_view_tree(e, d + 1, max, api_metadata)
      ]
    }
  end

  def expr_to_view_tree(%{op: :if, then_expr: t, else_expr: e}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "if",
      "label" => "",
      "children" => [
        expr_to_view_tree(t, d + 1, max, api_metadata),
        expr_to_view_tree(e, d + 1, max, api_metadata)
      ]
    }
  end

  def expr_to_view_tree(%{op: :case, subject: s, branches: branches}, d, max, api_metadata)
       when d < max and is_list(branches) do
    %{
      "type" => "case",
      "label" => "",
      "children" => [
        expr_to_view_tree(s, d + 1, max, api_metadata)
        | Enum.flat_map(branches, fn
            %{expr: expr} -> [expr_to_view_tree(expr, d + 1, max, api_metadata)]
            %{"expr" => expr} -> [expr_to_view_tree(expr, d + 1, max, api_metadata)]
            _ -> []
          end)
      ]
    }
  end

  def expr_to_view_tree(%{op: :case, subject: s}, d, max, _api_metadata) when d < max do
    %{"type" => "case", "label" => to_string(s), "children" => []}
  end

  def expr_to_view_tree(%{op: :record_literal, fields: fields}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "record",
      "label" => "#{length(fields)} fields",
      "children" =>
        Enum.map(fields, fn %{name: n, expr: e} ->
          %{
            "type" => "field",
            "label" => n,
            "children" => [expr_to_view_tree(e, d + 1, max, api_metadata)]
          }
        end)
    }
  end

  def expr_to_view_tree(
         %{op: :var_resolved, name: n, value_expr: value_expr},
         d,
         max,
         api_metadata
       )
       when d < max do
    %{
      "type" => "var",
      "label" => n,
      "children" => [expr_to_view_tree(value_expr, d + 1, max, api_metadata)],
      "op" => "var",
      "value" => n
    }
  end

  def expr_to_view_tree(%{op: :var, name: n}, _, _, _api_metadata) do
    %{"type" => "var", "label" => n, "children" => [], "op" => "var", "value" => n}
  end

  def expr_to_view_tree(%{op: :add_const, var: var, value: value}, d, max, api_metadata)
       when d < max do
    expr_to_view_tree(
      %{
        op: :call,
        name: "__add__",
        args: [%{op: :var, name: var}, %{op: :int_literal, value: value}]
      },
      d,
      max,
      api_metadata
    )
  end

  def expr_to_view_tree(%{op: :sub_const, var: var, value: value}, d, max, api_metadata)
       when d < max do
    expr_to_view_tree(
      %{
        op: :call,
        name: "__sub__",
        args: [%{op: :var, name: var}, %{op: :int_literal, value: value}]
      },
      d,
      max,
      api_metadata
    )
  end

  def expr_to_view_tree(%{op: :add_vars, left: left, right: right}, d, max, api_metadata)
       when d < max do
    expr_to_view_tree(
      %{
        op: :call,
        name: "__add__",
        args: [%{op: :var, name: left}, %{op: :var, name: right}]
      },
      d,
      max,
      api_metadata
    )
  end

  def expr_to_view_tree(%{op: :int_literal, value: v}, _, _, _api_metadata) when is_integer(v) do
    %{
      "type" => "expr",
      "label" => Integer.to_string(v),
      "children" => [],
      "op" => "int_literal",
      "value" => v
    }
  end

  def expr_to_view_tree(%{op: :float_literal, value: v}, _, _, _api_metadata)
       when is_number(v) do
    %{
      "type" => "expr",
      "label" => to_string(v),
      "children" => [],
      "op" => "float_literal",
      "value" => v
    }
  end

  def expr_to_view_tree(%{op: :string_literal, value: v}, _, _, _api_metadata)
       when is_binary(v) do
    %{
      "type" => "expr",
      "label" => inspect(v),
      "children" => [],
      "op" => "string_literal",
      "value" => v
    }
  end

  def expr_to_view_tree(%{op: :char_literal, value: v}, _, _, _api_metadata) when is_binary(v) do
    %{
      "type" => "expr",
      "label" => inspect(v),
      "children" => [],
      "op" => "char_literal",
      "value" => v
    }
  end

  def expr_to_view_tree(
         %{op: :field_access, arg: _arg, field: _field} = expr,
         _,
         _,
         _api_metadata
       ) do
    %{
      "type" => "expr",
      "label" => Support.field_access_label(expr),
      "children" => [],
      "op" => "field_access"
    }
  end

  def expr_to_view_tree(%{op: :tuple_first_expr, arg: arg}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "expr",
      "label" => "tuple_first_expr",
      "children" => [expr_to_view_tree(arg, d + 1, max, api_metadata)],
      "op" => "tuple_first_expr"
    }
  end

  def expr_to_view_tree(%{op: :tuple_second_expr, arg: arg}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "expr",
      "label" => "tuple_second_expr",
      "children" => [expr_to_view_tree(arg, d + 1, max, api_metadata)],
      "op" => "tuple_second_expr"
    }
  end

  def expr_to_view_tree(%{op: op}, _, _, _api_metadata) do
    %{"type" => "expr", "label" => to_string(op), "children" => [], "op" => to_string(op)}
  end

  def expr_to_view_tree(_, _, _, _api_metadata), do: ViewTree.view_tree_unknown()

  @spec normalize_view_expr(Types.ast_expr()) :: Types.ast_expr()
  defp normalize_view_expr(expr), do: inline_view_lets(expr, %{}, MapSet.new())

  @spec inline_view_lets(Types.ast_expr(), Types.binding_map(), MapSet.t()) :: Types.ast_expr()
  defp inline_view_lets(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings,
         seen
       )
       when is_binary(name) and is_map(bindings) do
    resolved_value = inline_view_lets(value_expr, bindings, seen)
    inline_view_lets(inner, Map.put(bindings, name, resolved_value), seen)
  end

  defp inline_view_lets(%{op: :var, name: name} = var, bindings, seen)
       when is_binary(name) and is_map(bindings) do
    if MapSet.member?(seen, name) do
      var
    else
      case Map.get(bindings, name) do
        nil ->
          var

        value_expr ->
          %{
            op: :var_resolved,
            name: name,
            value_expr: inline_view_lets(value_expr, bindings, MapSet.put(seen, name))
          }
      end
    end
  end

  defp inline_view_lets(map, bindings, seen) when is_map(map) do
    Enum.into(map, %{}, fn {k, v} -> {k, inline_view_lets(v, bindings, seen)} end)
  end

  defp inline_view_lets(list, bindings, seen) when is_list(list) do
    Enum.map(list, &inline_view_lets(&1, bindings, seen))
  end

  defp inline_view_lets(other, _bindings, _seen), do: other
end
