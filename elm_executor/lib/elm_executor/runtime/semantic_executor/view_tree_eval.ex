defmodule ElmExecutor.Runtime.SemanticExecutor.ViewTreeEval do
  @moduledoc false
  @dialyzer :no_match

  alias ElmExecutor.Runtime.SemanticExecutor.Execution

  alias ElmEx.CoreIR
  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Project
  alias ElmEx.IR.Lowerer
  alias ElmExecutor.Runtime.CoreIRContract
  alias ElmExecutor.Runtime.CoreIREvaluator
  alias ElmExecutor.Runtime.CoreIREvaluator.Types, as: EvalTypes
  alias ElmExecutor.Runtime.SemanticExecutor.Types, as: SemTypes
  alias ElmExecutor.Runtime.ViewTreeIntrinsics
  @doc """
  Evaluates a parser-derived rendered view node against the current runtime model.

  This is used by debugger UI code to annotate the source-shaped rendered hierarchy
  with the same values the semantic executor can derive for visual preview output.
  """
  @spec evaluate_view_tree_value(map(), map(), map()) :: EvalTypes.runtime_value() | nil
  def evaluate_view_tree_value(node, runtime_model, eval_context \\ %{})

  def evaluate_view_tree_value(node, runtime_model, eval_context)
      when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    eval_tree_expr_value(node, runtime_model, eval_context)
  end

  def evaluate_view_tree_value(_node, _runtime_model, _eval_context), do: nil

  def field_value_int(field_node, runtime_model, eval_context)
       when is_map(field_node) and is_map(runtime_model) and is_map(eval_context) do
    case node_children(field_node) do
      [value_node | _] -> eval_view_int(value_node, runtime_model, eval_context)
      _ -> nil
    end
  end

  def field_value_int(_field_node, _runtime_model, _eval_context), do: nil

  @spec eval_view_color(map(), map(), map()) :: integer() | nil
  def eval_view_color(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case eval_view_int(node, runtime_model, eval_context) do
      int when is_integer(int) ->
        int

      _ ->
        color_name =
          node
          |> Map.get("type", Map.get(node, :type, ""))
          |> to_string()
          |> String.trim()
          |> String.downcase()

        case color_name do
          "clearcolor" -> 0x00
          "black" -> 0xC0
          "white" -> 0xFF
          _ -> nil
        end
    end
  end

  def eval_view_color(_node, _runtime_model, _eval_context), do: nil

  @spec node_children(map()) :: [map()]
  def node_children(node) when is_map(node) do
    case node["children"] || node[:children] do
      list when is_list(list) ->
        Enum.filter(list, &is_map/1)

      _ ->
        type = to_string(node["type"] || node[:type] || "")
        op = to_string(node["op"] || node[:op] || "")
        fields = node["fields"] || node[:fields]

        if (type == "record" or (type == "expr" and op == "record_literal")) and is_map(fields) do
          fields
          |> Enum.map(fn {k, v} ->
            child =
              cond do
                is_map(v) -> v
                is_integer(v) -> %{"type" => "expr", "value" => v}
                is_float(v) -> %{"type" => "expr", "value" => trunc(v)}
                is_binary(v) -> %{"type" => "expr", "label" => v}
                true -> %{"type" => "expr", "label" => to_string(v)}
              end

            %{
              "type" => "field",
              "label" => to_string(k),
              "children" => [child]
            }
          end)
        else
          []
        end
    end
  end

  @spec eval_view_int(map(), map(), map()) :: integer() | nil
  def eval_view_int(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    val = node["value"] || node[:value]

    cond do
      is_integer(val) ->
        val

      is_float(val) ->
        trunc(val)

      is_binary(val) ->
        case Integer.parse(val) do
          {parsed, ""} -> parsed
          _ -> eval_view_int_fallback(node, runtime_model, eval_context)
        end

      true ->
        eval_view_int_fallback(node, runtime_model, eval_context)
    end
  end

  def eval_view_int(_node, _runtime_model, _eval_context), do: nil

  @spec eval_view_int_fallback(map(), map(), map()) :: integer() | nil
  defp eval_view_int_fallback(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    type = to_string(node["type"] || node[:type] || "")
    label = to_string(node["label"] || node[:label] || "")
    op = to_string(node["op"] || node[:op] || "")

    children =
      case node["children"] || node[:children] do
        list when is_list(list) -> Enum.filter(list, &is_map/1)
        _ -> []
      end

    expr_eval = eval_tree_expr_int(node, runtime_model, eval_context)

    cond do
      is_integer(expr_eval) ->
        expr_eval

      (type == "expr" and op == "field_access") or String.starts_with?(label, "model.") ->
        label
        |> String.replace_prefix("model.", "")
        |> then(&Map.get(runtime_model, &1))
        |> case do
          value when is_integer(value) -> value
          value when is_float(value) -> trunc(value)
          _ -> nil
        end

      type == "var" ->
        var_name = view_var_name(node)

        cond do
          is_integer(view_binding_value(var_name, runtime_model, eval_context)) ->
            view_binding_value(var_name, runtime_model, eval_context)

          is_float(view_binding_value(var_name, runtime_model, eval_context)) ->
            trunc(view_binding_value(var_name, runtime_model, eval_context))

          is_integer(Map.get(runtime_model, var_name)) ->
            Map.get(runtime_model, var_name)

          is_float(Map.get(runtime_model, var_name)) ->
            trunc(Map.get(runtime_model, var_name))

          true ->
            Enum.find_value(children, &eval_view_int(&1, runtime_model, eval_context))
        end

      type == "if" ->
        case selected_if_branch(children, runtime_model, eval_context) do
          %{} = branch -> eval_view_int(branch, runtime_model, eval_context)
          _ -> nil
        end

      type == "let" ->
        case apply_let_view_binding(node, runtime_model, eval_context) do
          {%{} = inner, ctx} -> eval_view_int(inner, runtime_model, ctx)
          _ -> nil
        end

      type == "call" or view_tree_int_call_type?(type) ->
        call_name = view_tree_int_call_name(node)
        args = Enum.map(children, &eval_view_int(&1, runtime_model, eval_context))

        if Enum.all?(args, &is_integer/1) do
          eval_int_call(call_name, args)
        else
          nil
        end

      true ->
        case eval_tree_expr_int(node, runtime_model, eval_context) do
          value when is_integer(value) ->
            value

          _ ->
            if type in ["if", "case"] do
              nil
            else
              Enum.find_value(children, &eval_view_int(&1, runtime_model, eval_context))
            end
        end
    end
  end

  defp eval_view_int_fallback(_node, _runtime_model, _eval_context), do: nil

  @spec selected_if_branch([map()], map(), map()) :: map() | nil
  def selected_if_branch(children, runtime_model, eval_context)
       when is_list(children) and is_map(runtime_model) and is_map(eval_context) do
    case children do
      [cond, then_branch, else_branch] when is_map(then_branch) and is_map(else_branch) ->
        if if_condition_truthy?(cond, runtime_model, eval_context), do: then_branch, else: else_branch

      [then_branch, else_branch] when is_map(then_branch) and is_map(else_branch) ->
        then_branch

      _ ->
        nil
    end
  end

  def selected_if_branch(_children, _runtime_model, _eval_context), do: nil

  @spec if_condition_truthy?(map(), map(), map()) :: boolean()
  defp if_condition_truthy?(cond_node, runtime_model, eval_context)
       when is_map(cond_node) and is_map(runtime_model) and is_map(eval_context) do
    case eval_tree_expr_value(cond_node, runtime_model, eval_context) do
      true -> true
      false -> false
      value when is_integer(value) -> value != 0
      _ -> false
    end
  end

  defp if_condition_truthy?(_cond_node, _runtime_model, _eval_context), do: false

  @spec apply_let_view_binding(map(), map(), map()) :: {map(), map()} | nil
  def apply_let_view_binding(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    name = to_string(node["label"] || node[:label] || "")
    children = node_children(node)

    case children do
      [value_node, inner_node] when is_map(value_node) and is_map(inner_node) and name != "" ->
        binding_value = eval_tree_expr_value(value_node, runtime_model, eval_context)

        bindings =
          eval_context
          |> Map.get(:view_param_bindings, %{})
          |> Map.put(name, binding_value)

        ctx = Map.put(eval_context, :view_param_bindings, bindings)
        {inner_node, ctx}

      _ ->
        nil
    end
  end

  def apply_let_view_binding(_node, _runtime_model, _eval_context), do: nil

  @spec eval_view_text(map(), map(), map()) :: String.t() | nil
  def eval_view_text(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    value = node["value"] || node[:value]
    label = to_string(node["label"] || node[:label] || "")
    op = to_string(node["op"] || node[:op] || "")

    from_field_access =
      cond do
        op == "field_access" and String.starts_with?(label, "model.") ->
          key = String.replace_prefix(label, "model.", "")
          model_value_by_key(runtime_model, key)

        true ->
          nil
      end

    from_expr = eval_tree_expr_value(node, runtime_model, eval_context)

    from_children =
      Enum.find_value(node_children(node), &eval_view_text(&1, runtime_model, eval_context))

    # Prefer freshly evaluated expressions over cached `value` annotations on view-tree nodes.
    [from_expr, from_field_access, from_children, value]
    |> Enum.find_value(&normalize_text_value/1)
  end

  def eval_view_text(_node, _runtime_model, _eval_context), do: nil

  @spec eval_tree_expr_value(map(), map(), map()) :: EvalTypes.runtime_value() | nil
  def eval_tree_expr_value(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case tree_node_to_expr(node) do
      nil ->
        nil

      expr ->
        case CoreIREvaluator.evaluate(expr, view_eval_env(runtime_model, eval_context), eval_context) do
          {:ok, value} -> value
          _ -> nil
        end
    end
  end

  def eval_tree_expr_value(_node, _runtime_model, _eval_context), do: nil

  @spec view_eval_env(map(), map()) :: map()
  defp view_eval_env(runtime_model, eval_context) when is_map(runtime_model) and is_map(eval_context) do
    bindings = Map.get(eval_context, :view_param_bindings) || %{}

    runtime_model
    |> Map.put("model", runtime_model)
    |> Map.merge(bindings)
  end

  @spec view_var_name(map()) :: String.t()
  def view_var_name(node) when is_map(node) do
    node
    |> then(fn n -> n["value"] || n[:value] || n["label"] || n[:label] || "" end)
    |> to_string()
  end

  @spec view_binding_value(String.t(), map(), map()) :: EvalTypes.runtime_value()
  def view_binding_value(name, runtime_model, eval_context)
       when is_binary(name) and name != "" and is_map(runtime_model) and is_map(eval_context) do
    Map.get(view_eval_env(runtime_model, eval_context), name)
  end

  def view_binding_value(_name, _runtime_model, _eval_context), do: nil

  @spec point_coords_from_value(EvalTypes.runtime_value()) :: SemTypes.point_pair()
  def point_coords_from_value(%{"ctor" => "Point", "args" => [x, y]})
       when is_integer(x) and is_integer(y),
       do: {:ok, [x, y]}

  def point_coords_from_value(%{ctor: "Point", args: [x, y]})
       when is_integer(x) and is_integer(y),
       do: {:ok, [x, y]}

  def point_coords_from_value(%{"x" => x, "y" => y}) when is_integer(x) and is_integer(y),
    do: {:ok, [x, y]}

  def point_coords_from_value(%{x: x, y: y}) when is_integer(x) and is_integer(y),
    do: {:ok, [x, y]}

  def point_coords_from_value(_value), do: :error

  @spec record_point_coords_from_node(map(), map(), map()) :: SemTypes.point_pair()
  def record_point_coords_from_node(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    fields =
      node
      |> node_children()
      |> Enum.filter(&(to_string(&1["type"] || &1[:type] || "") in ["field", "record_field"]))

    x_value =
      fields
      |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "x"))
      |> field_value_int(runtime_model, eval_context)

    y_value =
      fields
      |> Enum.find(&(to_string(&1["label"] || &1[:label] || "") == "y"))
      |> field_value_int(runtime_model, eval_context)

    if is_integer(x_value) and is_integer(y_value), do: {:ok, [x_value, y_value]}, else: :error
  end

  def record_point_coords_from_node(_node, _runtime_model, _eval_context), do: :error

  @spec normalize_text_value(EvalTypes.runtime_value()) :: String.t() | nil
  def normalize_text_value(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed != "", do: value, else: nil
  end

  def normalize_text_value(value) when is_integer(value), do: Integer.to_string(value)

  def normalize_text_value(value) when is_float(value),
    do: :erlang.float_to_binary(value, [:compact])

  def normalize_text_value(value) when is_list(value) do
    if List.ascii_printable?(value) do
      value
      |> List.to_string()
      |> normalize_text_value()
    else
      nil
    end
  end

  def normalize_text_value(_value), do: nil

  @spec model_value_by_key(map(), String.t()) :: EvalTypes.runtime_value() | nil
  def model_value_by_key(model, key) when is_map(model) and is_binary(key) do
    Map.get(model, key) ||
      Enum.find_value(model, fn
        {atom_key, value} when is_atom(atom_key) ->
          if Atom.to_string(atom_key) == key, do: value, else: nil

        _ ->
          nil
      end)
  end

  @spec eval_tree_expr_int(map(), map(), map()) :: integer() | nil
  def eval_tree_expr_int(node, runtime_model, eval_context)
       when is_map(node) and is_map(runtime_model) and is_map(eval_context) do
    case tree_node_to_expr(node) do
      nil ->
        nil

      expr ->
        case CoreIREvaluator.evaluate(expr, view_eval_env(runtime_model, eval_context), eval_context) do
          {:ok, value} when is_integer(value) -> value
          {:ok, value} when is_float(value) -> trunc(value)
          _ -> nil
        end
    end
  end

  def eval_tree_expr_int(_node, _runtime_model, _eval_context), do: nil

  @spec tree_node_to_expr(map()) :: SemTypes.expr()
  defp tree_node_to_expr(node) when is_map(node) do
    type = to_string(node["type"] || node[:type] || "")
    label = to_string(node["label"] || node[:label] || "")
    op = to_string(node["op"] || node[:op] || "")
    value = node["value"] || node[:value]
    children = (node["children"] || node[:children] || []) |> Enum.filter(&is_map/1)
    qualified_target = Map.get(node, "qualified_target") || Map.get(node, :qualified_target)

    cond do
      type == "var" and children != [] ->
        tree_node_to_expr(hd(children))

      type == "var" and label != "" ->
        %{"op" => :var, "name" => label}

      is_binary(qualified_target) and qualified_target != "" ->
        %{
          "op" => :qualified_call,
          "target" => qualified_target,
          "args" => Enum.map(children, &tree_node_to_expr/1)
        }

      type == "call" and label != "" ->
        int_call_expr(label, children)

      view_tree_int_call_type?(type) ->
        int_call_expr(view_tree_int_call_name(node), children)

      type != "" and type not in ["expr", "var", "field", "record", "group", "clear", "text"] and
          label == type ->
        int_call_expr(type, children)

      type == "expr" and op == "tuple2" and length(children) >= 2 ->
        left = tree_node_to_expr(Enum.at(children, 0))
        right = tree_node_to_expr(Enum.at(children, 1))

        if is_map(left) and is_map(right) do
          %{"op" => :tuple2, "left" => left, "right" => right}
        else
          nil
        end

      type == "expr" and op == "tuple_first_expr" and children != [] ->
        case tree_node_to_expr(hd(children)) do
          nil -> nil
          arg_expr -> %{"op" => :tuple_first_expr, "arg" => arg_expr}
        end

      type == "expr" and op == "tuple_second_expr" and children != [] ->
        case tree_node_to_expr(hd(children)) do
          nil -> nil
          arg_expr -> %{"op" => :tuple_second_expr, "arg" => arg_expr}
        end

      type == "expr" and op == "field_access" and String.starts_with?(label, "model.") ->
        %{
          "op" => :field_access,
          "arg" => %{"op" => :var, "name" => "model"},
          "field" => String.replace_prefix(label, "model.", "")
        }

      type == "expr" and op == "string_literal" and is_binary(value) ->
        %{"op" => :string_literal, "value" => value}

      type == "expr" and op == "int_literal" and is_integer(value) ->
        %{"op" => :int_literal, "value" => value}

      type == "expr" and is_integer(value) ->
        %{"op" => :int_literal, "value" => value}

      type == "expr" and is_binary(label) ->
        case Integer.parse(label) do
          {parsed, ""} -> %{"op" => :int_literal, "value" => parsed}
          _ -> nil
        end

      type == "if" ->
        case children do
          [cond, then_branch, else_branch] when is_map(then_branch) and is_map(else_branch) ->
            %{
              "op" => :if,
              "cond" => tree_node_to_expr(cond),
              "then_expr" => tree_node_to_expr(then_branch),
              "else_expr" => tree_node_to_expr(else_branch)
            }
            |> if_expr_when_complete()

          [then_branch, else_branch] when is_map(then_branch) and is_map(else_branch) ->
            %{
              "op" => :if,
              "cond" => %{"op" => :bool_literal, "value" => true},
              "then_expr" => tree_node_to_expr(then_branch),
              "else_expr" => tree_node_to_expr(else_branch)
            }
            |> if_expr_when_complete()

          _ ->
            nil
        end

      type == "let" and label != "" ->
        case children do
          [value_node, inner_node] when is_map(value_node) and is_map(inner_node) ->
            with %{} = value_expr <- tree_node_to_expr(value_node),
                 %{} = in_expr <- tree_node_to_expr(inner_node) do
              %{"op" => :let_in, "name" => label, "value_expr" => value_expr, "in_expr" => in_expr}
            else
              _ -> nil
            end

          _ ->
            nil
        end

      true ->
        nil
    end
  end

  defp tree_node_to_expr(_), do: nil

  @spec if_expr_when_complete(map()) :: map() | nil
  defp if_expr_when_complete(%{"cond" => cond, "then_expr" => then_e, "else_expr" => else_e})
       when is_map(cond) and is_map(then_e) and is_map(else_e),
       do: %{"op" => :if, "cond" => cond, "then_expr" => then_e, "else_expr" => else_e}

  defp if_expr_when_complete(_), do: nil

  @spec view_tree_int_call_type?(String.t()) :: boolean()
  defp view_tree_int_call_type?(type) when is_binary(type),
    do: ViewTreeIntrinsics.int_call_name?(type)
  defp view_tree_int_call_type?(_type), do: false

  @spec view_tree_int_call_name(map()) :: String.t()
  defp view_tree_int_call_name(node) when is_map(node) do
    type = to_string(node["type"] || node[:type] || "")
    label = to_string(node["label"] || node[:label] || "")

    cond do
      type == "call" and label != "" -> label
      view_tree_int_call_type?(type) -> type
      true -> label
    end
  end

  @spec int_call_expr(String.t(), [map()]) :: map() | nil
  defp int_call_expr(name, children) when is_binary(name) and is_list(children) do
    args = Enum.map(children, &tree_node_to_expr/1)

    if Enum.all?(args, &is_map/1) do
      %{"op" => :call, "name" => name, "args" => args}
    else
      nil
    end
  end

  @spec eval_int_call(String.t(), [integer() | nil]) :: integer() | nil
  defp eval_int_call("__add__", [a, b]), do: a + b
  defp eval_int_call("__sub__", [a, b]), do: a - b
  defp eval_int_call("__mul__", [a, b]), do: a * b
  defp eval_int_call("__pow__", [a, b]) when b >= 0, do: round(:math.pow(a, b))
  defp eval_int_call("__fdiv__", [_a, 0]), do: nil
  defp eval_int_call("__fdiv__", [a, b]), do: trunc(a / b)
  defp eval_int_call("__idiv__", [_a, 0]), do: nil
  defp eval_int_call("__idiv__", [a, b]), do: div(a, b)

  defp eval_int_call("modBy", [by, value]) when is_integer(by) and by > 0 and is_integer(value),
    do: Integer.mod(value, by)

  defp eval_int_call("Basics.modBy", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: Integer.mod(value, by)

  defp eval_int_call("basics.modby", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: Integer.mod(value, by)

  defp eval_int_call("remainderBy", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: rem(value, by)

  defp eval_int_call("Basics.remainderBy", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: rem(value, by)

  defp eval_int_call("basics.remainderby", [by, value])
       when is_integer(by) and by > 0 and is_integer(value),
       do: rem(value, by)

  defp eval_int_call("max", [a, b]), do: max(a, b)
  defp eval_int_call("min", [a, b]), do: min(a, b)

  defp eval_int_call("abs", [value]) when is_integer(value), do: abs(value)
  defp eval_int_call("Basics.abs", [value]) when is_integer(value), do: abs(value)
  defp eval_int_call("negate", [value]) when is_integer(value), do: -value
  defp eval_int_call("Basics.negate", [value]) when is_integer(value), do: -value

  defp eval_int_call("round", [value]) when is_integer(value), do: value
  defp eval_int_call("Basics.round", [value]) when is_integer(value), do: value

  defp eval_int_call("clamp", [low, high, value])
       when is_integer(low) and is_integer(high) and is_integer(value),
       do: max(low, min(high, value))

  defp eval_int_call("Basics.clamp", [low, high, value])
       when is_integer(low) and is_integer(high) and is_integer(value),
       do: max(low, min(high, value))

  defp eval_int_call("clampInt", [low, high, value])
       when is_integer(low) and is_integer(high) and is_integer(value),
       do: max(low, min(high, value))

  defp eval_int_call(_name, _args), do: nil

  @spec extract_ints(String.t()) :: [integer()]
  def extract_ints(text) when is_binary(text) do
    Regex.scan(~r/-?\d+/, text)
    |> Enum.map(fn [raw] -> String.to_integer(raw) end)
  end

end
