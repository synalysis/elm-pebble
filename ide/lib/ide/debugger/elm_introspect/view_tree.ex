defmodule Ide.Debugger.ElmIntrospect.ViewTree do
  @moduledoc ""

  alias ElmEx.Frontend.Module
  alias Ide.Debugger.ElmIntrospect
  alias Ide.Debugger.ElmIntrospect.Types
  alias Ide.Debugger.RuntimeArtifacts

  @spec function_type_key(String.t(), String.t(), non_neg_integer()) :: String.t()
  defp function_type_key(module_name, function_name, arity)
       when is_binary(module_name) and is_binary(function_name) and is_integer(arity) do
    module_name <> "|" <> function_name <> "|" <> Integer.to_string(arity)
  end

  @spec return_type_from_signature(String.t()) :: String.t()
  defp return_type_from_signature(type) when is_binary(type) do
    type
    |> String.split("->")
    |> List.last()
    |> to_string()
    |> String.trim()
  end

  @doc """
  Returns true when a parser-derived view tree root still needs runtime Core IR evaluation.
  """
  @spec parser_expression_view?(Types.introspect_snapshot() | map()) :: boolean()
  def parser_expression_view?(introspect) when is_map(introspect) do
    ei = RuntimeArtifacts.introspect(introspect) || introspect
    root = Map.get(ei, "view_tree") || %{}
    parser_expression_view_tree_node?(root, ei)
  end

  def parser_expression_view?(_), do: false

  @doc """
  Returns true when a parser-derived view tree node is still an unevaluated view expression.

  Uses declared return types and structural shapes from introspection metadata, not helper names.
  """
  @spec parser_expression_view_tree_node?(Types.view_tree_node(), Types.elm_introspect() | map()) ::
          boolean()
  def parser_expression_view_tree_node?(node, ei) when is_map(node) and is_map(ei) do
    type = Map.get(node, "type")

    cond do
      runtime_drawable_view_root_type?(type) ->
        false

      parser_expression_structural_type?(type) ->
        true

      view_tree_call_returns_ui_node?(node, ei) ->
        true

      ui_node_call_with_unevaluated_children?(node, ei) ->
        true

      true ->
        false
    end
  end

  def parser_expression_view_tree_node?(_, _), do: false

  @spec parser_ui_node_wrapper_type?(Types.view_tree_node()) :: boolean()
  defp parser_ui_node_wrapper_type?(node) when is_map(node) do
    case Map.get(node, "type") do
      "toUiNode" ->
        true

      type when is_binary(type) ->
        String.ends_with?(type, "toUiNode")

      _ ->
        qualified = Map.get(node, "qualified_target") || Map.get(node, "target")

        is_binary(qualified) and String.ends_with?(qualified, "toUiNode")
    end
  end

  @spec ui_node_call_with_unevaluated_children?(map(), map()) :: boolean()
  defp ui_node_call_with_unevaluated_children?(node, ei) when is_map(node) and is_map(ei) do
    (view_tree_call_returns_ui_node?(node, ei) or parser_ui_node_wrapper_type?(node)) and
      not parser_expression_structural_type?(Map.get(node, "type")) and
      Enum.any?(List.wrap(Map.get(node, "children")), fn child ->
        is_map(child) and parser_expression_view_tree_node?(child, ei)
      end)
  end

  defp ui_node_call_with_unevaluated_children?(_, _), do: false

  @doc ""
  @spec runtime_drawable_view_root_type?(String.t() | nil) :: boolean()
  def runtime_drawable_view_root_type?(type) when type in ["windowStack", "WindowStack"], do: true
  def runtime_drawable_view_root_type?(_), do: false

  @doc ""
  @spec ui_node_type_signature?(String.t() | nil) :: boolean()
  def ui_node_type_signature?(type) when is_binary(type) do
    type
    |> String.replace(~r/\s+/, "")
    |> String.downcase()
    |> String.ends_with?("uinode")
  end

  def ui_node_type_signature?(_), do: false

  @doc ""
  @spec parser_expression_combinator_type?(String.t(), Types.elm_introspect() | map()) :: boolean()
  def parser_expression_combinator_type?(type, introspect \\ %{})

  def parser_expression_combinator_type?(type, introspect)
      when is_binary(type) and is_map(introspect) and map_size(introspect) > 0 do
    ei = RuntimeArtifacts.introspect(introspect) || introspect
    parser_expression_view_tree_node?(%{"type" => type}, ei)
  end

  def parser_expression_combinator_type?(type, _introspect) when is_binary(type),
    do: parser_expression_structural_type?(type)

  def parser_expression_combinator_type?(_, _), do: false

  @doc ""
  @spec parser_expression_structural_type?(String.t() | nil) :: boolean()
  def parser_expression_structural_type?(type)
      when type in [
             "append",
             "CanvasLayer",
             "List",
             "tuple2",
             "call",
             "expr",
             "var",
             "withDefault",
             "if",
             "case",
             "let"
           ],
      do: true

  def parser_expression_structural_type?(_), do: false

  @spec function_render_trees(Module.t(), Types.view_build_metadata()) :: %{
          optional(String.t()) => Types.view_tree()
        }
  def function_render_trees(%Module{} = mod, api_metadata) when is_map(api_metadata) do
    Map.get(api_metadata, :function_types, %{})
    |> Enum.reduce(%{}, fn {key, signature}, acc ->
      if render_op_function_return_type?(signature) do
        case String.split(key, "|", parts: 3) do
          [_module, function_name, _arity] ->
            case ElmIntrospect.find_function_definition(mod, function_name) do
              %{expr: expr} when not is_nil(expr) ->
                Map.put(acc, key, expr_to_view_tree(expr, 0, 40, api_metadata))

              _ ->
                acc
            end

          _ ->
            acc
        end
      else
        acc
      end
    end)
  end

  def function_render_trees(_mod, _api_metadata), do: %{}

  @spec render_op_function_return_type?(String.t()) :: boolean()
  defp render_op_function_return_type?(signature) when is_binary(signature) do
    normalized =
      signature
      |> String.replace(~r/\s+/, "")
      |> String.downcase()

    String.match?(normalized, ~r/list.*renderop/) or String.match?(normalized, ~r/->renderop$/)
  end

  defp render_op_function_return_type?(_signature), do: false

  @spec first_non_nil([Types.wire_pick()]) :: Types.wire_pick()
  defp first_non_nil(values) when is_list(values) do
    Enum.find(values, &(!is_nil(&1)))
  end

  @spec view_tree_call_returns_ui_node?(map(), map()) :: boolean()
  defp view_tree_call_returns_ui_node?(node, ei) when is_map(node) and is_map(ei) do
    case Map.get(node, "return_kind") do
      "ui_node" -> true
      "render_op" -> false
      _ -> view_tree_call_returns_ui_node_from_target?(view_tree_call_target(node), call_tree_arity(node), ei)
    end
  end

  defp view_tree_call_returns_ui_node?(_, _), do: false

  @spec view_tree_call_returns_ui_node_from_target?(String.t() | nil, non_neg_integer(), map()) ::
          boolean()
  defp view_tree_call_returns_ui_node_from_target?(target, arity, ei)
       when is_binary(target) and is_integer(arity) and is_map(ei) do
    with types when is_map(types) <- Map.get(ei, "function_types"),
         {module_name, function_name} <- resolve_view_tree_call_target(target, ei),
         key <- function_type_key(module_name, function_name, arity),
         type when is_binary(type) <-
           Map.get(types, key) || find_function_type_signature(types, module_name, function_name) do
      ui_node_type_signature?(return_type_from_signature(type)) or
        render_ops_to_ui_node_signature?(type)
    else
      _ -> false
    end
  end

  defp view_tree_call_returns_ui_node_from_target?(_target, _arity, _ei), do: false

  @spec view_tree_call_return_kind(String.t(), non_neg_integer(), map()) :: String.t() | nil
  defp view_tree_call_return_kind(target, arity, api_metadata)
       when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    cond do
      view_tree_call_returns_ui_node_from_target?(target, arity, api_metadata) ->
        "ui_node"

      scene_root_call_return_kind?(target, arity, api_metadata) ->
        "ui_node"

      render_op_call_from_target?(target, arity, api_metadata) ->
        "render_op"

      true ->
        infer_local_function_return_kind(target, arity, api_metadata)
    end
  end

  defp view_tree_call_return_kind(_target, _arity, _api_metadata), do: nil

  @spec infer_local_function_return_kind(String.t(), non_neg_integer(), map()) :: String.t() | nil
  defp infer_local_function_return_kind(target, arity, api_metadata)
       when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    with %Module{} = mod <- Map.get(api_metadata, :module_ref),
         {module_name, function_name} <- resolve_view_tree_call_target(target, api_metadata),
         true <- module_name == mod.name,
         %{args: args, expr: expr} <- ElmIntrospect.find_function_definition(mod, function_name),
         true <- length(List.wrap(args)) == arity do
      infer_expr_return_kind(expr, api_metadata)
    else
      _ -> nil
    end
  end

  defp infer_local_function_return_kind(_target, _arity, _api_metadata), do: nil

  @spec infer_expr_return_kind(Types.ast_expr(), map()) :: String.t() | nil
  defp infer_expr_return_kind(expr, api_metadata) when is_map(expr) and is_map(api_metadata) do
    case expr do
      %{op: :qualified_call, target: target, args: args} when is_list(args) ->
        view_tree_call_return_kind(target, length(args), api_metadata)

      %{op: :call, name: name, args: args} when is_list(args) ->
        view_tree_call_return_kind(name, length(args), api_metadata)

      %{op: :expr, expr: inner} ->
        infer_expr_return_kind(inner, api_metadata)

      %{op: :let_in, in_expr: inner} ->
        infer_expr_return_kind(inner, api_metadata)

      _ ->
        nil
    end
  end

  defp infer_expr_return_kind(_expr, _api_metadata), do: nil

  @spec render_op_call_from_target?(String.t(), non_neg_integer(), map()) :: boolean()
  defp render_op_call_from_target?(target, arity, api_metadata)
       when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    with types when is_map(types) <- Map.get(api_metadata, "function_types"),
         {module_name, function_name} <- resolve_view_tree_call_target(target, api_metadata),
         key <- function_type_key(module_name, function_name, arity),
         type when is_binary(type) <-
           Map.get(types, key) || find_function_type_signature(types, module_name, function_name) do
      render_op_function_return_type?(type)
    else
      _ -> false
    end
  end

  defp render_op_call_from_target?(_target, _arity, _api_metadata), do: false

  @spec scene_root_call_return_kind?(String.t(), non_neg_integer(), map()) :: boolean()
  defp scene_root_call_return_kind?(target, arity, api_metadata)
       when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    with types when is_map(types) <- Map.get(api_metadata, "function_types") || Map.get(api_metadata, :function_types),
         {module_name, function_name} <- resolve_view_tree_call_target(target, api_metadata),
         key <- function_type_key(module_name, function_name, arity),
         type when is_binary(type) <-
           Map.get(types, key) || find_function_type_signature(types, module_name, function_name),
         return_type when is_binary(return_type) <- return_type_from_signature(type) do
      ui_node_type_signature?(return_type) or
        runtime_drawable_view_root_type?(view_type_name(return_type))
    else
      _ -> false
    end
  end

  defp scene_root_call_return_kind?(_target, _arity, _api_metadata), do: false

  @spec resolve_view_tree_call_target(String.t(), map()) :: {String.t(), String.t()} | nil
  defp resolve_view_tree_call_target(target, metadata) when is_binary(target) and is_map(metadata) do
    resolution =
      case metadata do
        %{aliases: _} -> metadata
        %{"aliases" => _} -> metadata
        _ -> introspect_call_resolution(metadata)
      end

    case resolve_source_call(target, resolution) do
      {module_name, function_name} when is_binary(module_name) and is_binary(function_name) ->
        {module_name, function_name}

      _ ->
        module_name = Map.get(metadata, "module") || Map.get(metadata, :module)

        if is_binary(module_name) and not String.contains?(target, ".") do
          {module_name, target}
        end
    end
  end

  defp resolve_view_tree_call_target(_target, _metadata), do: nil

  @spec maybe_put_view_tree_return_kind(map(), String.t(), non_neg_integer(), map()) :: map()
  defp maybe_put_view_tree_return_kind(node, target, arity, api_metadata)
       when is_map(node) and is_binary(target) and is_map(api_metadata) do
    case view_tree_call_return_kind(target, arity, api_metadata) do
      kind when is_binary(kind) -> Map.put(node, "return_kind", kind)
      _ -> node
    end
  end

  defp maybe_put_view_tree_return_kind(node, _target, _arity, _api_metadata), do: node

  @spec view_tree_call_target_name(String.t(), map()) :: String.t()
  defp view_tree_call_target_name(name, api_metadata) when is_binary(name) and is_map(api_metadata) do
    if String.contains?(name, ".") do
      name
    else
      module_name = Map.get(api_metadata, "module") || Map.get(api_metadata, :module) || ""

      if module_name != "", do: module_name <> "." <> name, else: name
    end
  end

  @spec view_tree_call_target(map()) :: String.t() | nil
  defp view_tree_call_target(node) when is_map(node) do
    Map.get(node, "qualified_target") ||
      case {Map.get(node, "label"), Map.get(node, "type")} do
        {name, name} when is_binary(name) -> name
        {label, _} when is_binary(label) -> label
        {_, type} when is_binary(type) -> type
        _ -> nil
      end
  end

  @spec render_ops_to_ui_node_signature?(String.t()) :: boolean()
  defp render_ops_to_ui_node_signature?(type) when is_binary(type) do
    type
    |> String.replace(~r/\s+/, "")
    |> String.downcase()
    |> then(fn normalized ->
      String.match?(normalized, ~r/listrenderop->.*uinode$/) or
        String.match?(normalized, ~r/\(.*listrenderop.*\)->.*uinode$/)
    end)
  end

  @spec introspect_call_resolution(map()) :: map()
  defp introspect_call_resolution(ei) when is_map(ei) do
    aliases =
      (Map.get(ei, "import_entries") || [])
      |> Enum.reduce(%{}, fn entry, acc ->
        module_name = Map.get(entry, "module")
        alias_name = Map.get(entry, "as")

        acc
        |> put_module_alias(module_name, module_name)
        |> put_module_alias(alias_name, module_name)
        |> put_module_alias(module_short_name(module_name), module_name)
      end)

    unqualified =
      (Map.get(ei, "import_entries") || [])
      |> Enum.reduce(%{}, fn entry, acc ->
        case Map.get(entry, "exposing") do
          names when is_list(names) ->
            Enum.reduce(names, acc, fn name, inner_acc ->
              if is_binary(name),
                do: Map.put(inner_acc, name, Map.get(entry, "module")),
                else: inner_acc
            end)

          _ ->
            acc
        end
      end)

    %{aliases: aliases, unqualified: unqualified}
  end

  @spec call_tree_arity(map()) :: non_neg_integer()
  defp call_tree_arity(root) when is_map(root) do
    root
    |> Map.get("children", [])
    |> case do
      children when is_list(children) -> length(children)
      _ -> 0
    end
  end

  @spec find_function_type_signature(map(), String.t(), String.t()) :: String.t() | nil
  defp find_function_type_signature(types, module_name, function_name)
       when is_map(types) and is_binary(module_name) and is_binary(function_name) do
    prefix = module_name <> "|" <> function_name <> "|"

    types
    |> Enum.find_value(fn {key, type} ->
      if is_binary(key) and String.starts_with?(key, prefix), do: type
    end)
  end

  @spec case_analysis(Types.ast_expr() | nil, Types.param_list()) :: Types.case_branch_labels()
  def case_analysis(nil, _), do: {[], nil}

  def case_analysis(expr, view_params) when is_list(view_params) do
    allowed = view_case_subjects(view_params)

    {peeled, bindings} = ElmIntrospect.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if view_case_subject_allowed?(subj, allowed, view_params, bindings) do
          subject_text = ElmIntrospect.case_subject_text(subj, bindings)

          labels =
            Enum.map(branches, fn
              %{pattern: p} -> ElmIntrospect.pattern_branch_label(p)
              _ -> "?"
            end)

          {labels, subject_text}
        else
          {[], nil}
        end

      _ ->
        {[], nil}
    end
  end

  def case_analysis(_, _), do: {[], nil}

  @spec view_case_subjects(Types.param_list()) :: Types.param_list()
  defp view_case_subjects(view_params) when is_list(view_params) do
    base = ["model"]

    case List.first(view_params) do
      first when is_binary(first) and first != "" and first != "_" ->
        Enum.uniq([first | base])

      _ ->
        base
    end
  end

  @spec view_case_subject_allowed?(Types.case_subject(), Types.param_list(), Types.param_list(), Types.binding_map()) ::
          boolean()
  defp view_case_subject_allowed?(subj, allowed, view_params, bindings)
       when is_list(allowed) and is_list(view_params) and is_map(bindings) do
    case ElmIntrospect.case_subject_text(subj, bindings) do
      "" ->
        false

      text ->
        Enum.member?(allowed, text) or view_case_param_prefix?(text, List.first(view_params))
    end
  end

  @spec view_case_param_prefix?(String.t(), Types.ast_expr()) :: boolean()
  defp view_case_param_prefix?(subj, param) when is_binary(param) and param not in ["", "_"] do
    String.starts_with?(subj, param <> ".")
  end

  defp view_case_param_prefix?(_subj, _param), do: false

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

  @spec expr_to_view_tree(Types.ast_expr() | nil, non_neg_integer(), non_neg_integer(), map()) :: Types.view_tree()
  defp expr_to_view_tree(nil, _, _, _api_metadata), do: view_tree_unknown()

  defp expr_to_view_tree(%{op: :expr, expr: inner}, d, max, api_metadata) when d < max do
    expr_to_view_tree(inner, d, max, api_metadata)
  end

  defp expr_to_view_tree(%{op: :expr, value_expr: inner}, d, max, api_metadata) when d < max do
    expr_to_view_tree(inner, d, max, api_metadata)
  end

  defp expr_to_view_tree(%{op: :expr, in_expr: inner}, d, max, api_metadata) when d < max do
    expr_to_view_tree(inner, d, max, api_metadata)
  end

  defp expr_to_view_tree(%{op: op} = expr, d, max, api_metadata)
       when d < max and (op == :list_literal or op == "list_literal") do
    items =
      first_non_nil([
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

  defp expr_to_view_tree(%{op: :tuple2, left: left, right: right}, d, max, api_metadata)
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

  defp expr_to_view_tree(%{op: :qualified_call, target: t, args: args}, d, max, api_metadata)
       when d < max do
    arity = length(args)

    %{
      "type" => view_type_name(t),
      "qualified_target" => t,
      "label" => view_arg_label(args),
      "arg_names" => source_call_arg_names(t, arity, api_metadata),
      "children" => Enum.map(args, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
    |> maybe_put_view_tree_return_kind(t, arity, api_metadata)
  end

  defp expr_to_view_tree(%{op: :constructor_call, target: t, args: args}, d, max, api_metadata)
       when d < max do
    arity = length(args)

    %{
      "type" => view_type_name(t),
      "qualified_target" => t,
      "label" => view_arg_label(args),
      "arg_names" => source_call_arg_names(t, arity, api_metadata),
      "children" => Enum.map(args, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
    |> maybe_put_view_tree_return_kind(t, arity, api_metadata)
  end

  defp expr_to_view_tree(%{op: :call, name: name, args: args}, d, max, api_metadata)
       when d < max do
    arity = length(args)
    target = view_tree_call_target_name(name, api_metadata)

    %{
      "type" => internal_arithmetic_view_type(name),
      "qualified_target" => target,
      "label" => name,
      "arg_names" => source_call_arg_names(target, arity, api_metadata),
      "children" => Enum.map(args, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
    |> maybe_put_view_tree_return_kind(target, arity, api_metadata)
  end

  defp expr_to_view_tree(%{op: :lambda, body: body}, d, max, api_metadata) when d < max do
    expr_to_view_tree(body, d + 1, max, api_metadata)
  end

  defp expr_to_view_tree(%{op: :let_in, name: name, value_expr: value, in_expr: inner}, d, max, api_metadata)
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

  defp expr_to_view_tree(%{op: :if, cond: cond, then_expr: t, else_expr: e}, d, max, api_metadata)
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

  defp expr_to_view_tree(%{op: :if, then_expr: t, else_expr: e}, d, max, api_metadata)
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

  defp expr_to_view_tree(%{op: :case, subject: s, branches: branches}, d, max, api_metadata)
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

  defp expr_to_view_tree(%{op: :case, subject: s}, d, max, _api_metadata) when d < max do
    %{"type" => "case", "label" => to_string(s), "children" => []}
  end

  defp expr_to_view_tree(%{op: :record_literal, fields: fields}, d, max, api_metadata)
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

  defp expr_to_view_tree(
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

  defp expr_to_view_tree(%{op: :var, name: n}, _, _, _api_metadata) do
    %{"type" => "var", "label" => n, "children" => [], "op" => "var", "value" => n}
  end

  defp expr_to_view_tree(%{op: :add_const, var: var, value: value}, d, max, api_metadata)
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

  defp expr_to_view_tree(%{op: :sub_const, var: var, value: value}, d, max, api_metadata)
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

  defp expr_to_view_tree(%{op: :add_vars, left: left, right: right}, d, max, api_metadata)
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

  defp expr_to_view_tree(%{op: :int_literal, value: v}, _, _, _api_metadata) when is_integer(v) do
    %{
      "type" => "expr",
      "label" => Integer.to_string(v),
      "children" => [],
      "op" => "int_literal",
      "value" => v
    }
  end

  defp expr_to_view_tree(%{op: :float_literal, value: v}, _, _, _api_metadata)
       when is_number(v) do
    %{
      "type" => "expr",
      "label" => to_string(v),
      "children" => [],
      "op" => "float_literal",
      "value" => v
    }
  end

  defp expr_to_view_tree(%{op: :string_literal, value: v}, _, _, _api_metadata)
       when is_binary(v) do
    %{
      "type" => "expr",
      "label" => inspect(v),
      "children" => [],
      "op" => "string_literal",
      "value" => v
    }
  end

  defp expr_to_view_tree(%{op: :char_literal, value: v}, _, _, _api_metadata) when is_binary(v) do
    %{
      "type" => "expr",
      "label" => inspect(v),
      "children" => [],
      "op" => "char_literal",
      "value" => v
    }
  end

  defp expr_to_view_tree(
         %{op: :field_access, arg: _arg, field: _field} = expr,
         _,
         _,
         _api_metadata
       ) do
    %{
      "type" => "expr",
      "label" => field_access_label(expr),
      "children" => [],
      "op" => "field_access"
    }
  end

  defp expr_to_view_tree(%{op: :tuple_first_expr, arg: arg}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "expr",
      "label" => "tuple_first_expr",
      "children" => [expr_to_view_tree(arg, d + 1, max, api_metadata)],
      "op" => "tuple_first_expr"
    }
  end

  defp expr_to_view_tree(%{op: :tuple_second_expr, arg: arg}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "expr",
      "label" => "tuple_second_expr",
      "children" => [expr_to_view_tree(arg, d + 1, max, api_metadata)],
      "op" => "tuple_second_expr"
    }
  end

  defp expr_to_view_tree(%{op: op}, _, _, _api_metadata) do
    %{"type" => "expr", "label" => to_string(op), "children" => [], "op" => to_string(op)}
  end

  defp expr_to_view_tree(_, _, _, _api_metadata), do: view_tree_unknown()

  @spec view_tree_unknown() :: Types.view_tree()
  defp view_tree_unknown, do: %{"type" => "unknown", "label" => "", "children" => []}

  @spec annotate_view_tree_sources(Types.view_tree(), map()) :: Types.view_tree()
  defp annotate_view_tree_sources(tree, api_metadata)
       when is_map(tree) and is_map(api_metadata) do
    {annotated, _counters} = annotate_view_tree_sources(tree, api_metadata, %{})
    annotated
  end

  defp annotate_view_tree_sources(tree, _api_metadata), do: tree

  @spec annotate_view_tree_sources(Types.view_tree(), map(), map()) :: {Types.view_tree(), map()}
  defp annotate_view_tree_sources(node, api_metadata, counters)
       when is_map(node) and is_map(api_metadata) and is_map(counters) do
    {children, counters} =
      node
      |> Map.get("children", [])
      |> List.wrap()
      |> Enum.map_reduce(counters, &annotate_view_tree_sources(&1, api_metadata, &2))

    node = Map.put(node, "children", children)

    case view_tree_source_target(node) do
      target when is_binary(target) and target != "" ->
        {maybe_put_view_tree_source(node, target, api_metadata, counters),
         increment_source_counter(counters, target)}

      _ ->
        {node, counters}
    end
  end

  defp annotate_view_tree_sources(other, _api_metadata, counters), do: {other, counters}

  @spec view_tree_source_target(map()) :: String.t() | nil
  defp view_tree_source_target(%{"qualified_target" => target}) when is_binary(target), do: target
  defp view_tree_source_target(%{qualified_target: target}) when is_binary(target), do: target

  defp view_tree_source_target(%{"type" => "call", "label" => label}) when is_binary(label),
    do: label

  defp view_tree_source_target(%{type: "call", label: label}) when is_binary(label), do: label
  defp view_tree_source_target(_node), do: nil

  @spec maybe_put_view_tree_source(map(), String.t(), map(), map()) :: map()
  defp maybe_put_view_tree_source(node, target, api_metadata, counters) do
    index = Map.get(counters, target, 0)

    case target |> source_locations_for_target(api_metadata) |> source_location_at(index) do
      %{} = source -> Map.put(node, "source", source)
      _ -> node
    end
  end

  @spec increment_source_counter(map(), String.t()) :: map()
  defp increment_source_counter(counters, target) when is_map(counters) and is_binary(target) do
    Map.update(counters, target, 1, &(&1 + 1))
  end

  @spec source_location_at([map()], non_neg_integer()) :: map() | nil
  defp source_location_at([], _index), do: nil

  defp source_location_at(locations, index) when is_list(locations) and is_integer(index) do
    Enum.at(locations, index) || List.last(locations)
  end

  @spec source_locations_for_target(String.t(), map()) :: [map()]
  defp source_locations_for_target(target, api_metadata)
       when is_binary(target) and is_map(api_metadata) do
    lines = Map.get(api_metadata, :source_lines, [])
    path = Map.get(api_metadata, :source_path)
    names = source_call_names(target, api_metadata)

    lines
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      case source_call_name_on_line(line, names) do
        nil ->
          []

        call ->
          [%{"path" => path, "line" => line_no, "call" => call}]
      end
    end)
  end

  defp source_locations_for_target(_target, _api_metadata), do: []

  @spec source_call_names(String.t(), map()) :: [String.t()]
  defp source_call_names(target, api_metadata) when is_binary(target) and is_map(api_metadata) do
    resolved = resolve_source_call(target, api_metadata)

    names =
      case resolved do
        {module_name, function_name} when is_binary(module_name) and is_binary(function_name) ->
          aliases =
            api_metadata
            |> Map.get(:aliases, %{})
            |> Enum.flat_map(fn
              {alias_name, ^module_name} when is_binary(alias_name) -> [alias_name]
              _ -> []
            end)

          unqualified =
            if Map.get(Map.get(api_metadata, :unqualified, %{}), function_name) == module_name,
              do: [function_name],
              else: []

          Enum.map(aliases, &"#{&1}.#{function_name}") ++ unqualified

        _ ->
          []
      end

    ([target] ++ names)
    |> Enum.filter(&(is_binary(&1) and &1 != ""))
    |> Enum.uniq()
    |> Enum.sort_by(&String.length/1, :desc)
  end

  @spec source_call_name_on_line(String.t(), [String.t()]) :: String.t() | nil
  defp source_call_name_on_line(line, names) when is_binary(line) and is_list(names) do
    line =
      line
      |> String.split("--", parts: 2)
      |> List.first()
      |> to_string()

    Enum.find(names, fn name ->
      Regex.match?(~r/(^|[^A-Za-z0-9_'])#{Regex.escape(name)}([^A-Za-z0-9_']|$)/, line)
    end)
  end

  defp source_call_name_on_line(_line, _names), do: nil

  @spec output_source_locations(map()) :: map()
  def output_source_locations(api_metadata) when is_map(api_metadata) do
    %{
      "clear" => ["Pebble.Ui.clear"],
      "round_rect" => ["Pebble.Ui.roundRect"],
      "rect" => ["Pebble.Ui.rect"],
      "fill_rect" => ["Pebble.Ui.fillRect"],
      "line" => ["Pebble.Ui.line"],
      "circle" => ["Pebble.Ui.circle"],
      "fill_circle" => ["Pebble.Ui.fillCircle"],
      "pixel" => ["Pebble.Ui.pixel"],
      "text" => ["Pebble.Ui.text"],
      "text_int" => ["Pebble.Ui.textInt", "Pebble.Ui.textIntWithFont"],
      "text_label" => ["Pebble.Ui.textLabel", "Pebble.Ui.textLabelWithFont"],
      "bitmap_in_rect" => ["Pebble.Ui.bitmapInRect", "Pebble.Ui.drawBitmapInRect"],
      "rotated_bitmap" => ["Pebble.Ui.rotatedBitmap"],
      "vector_at" => ["Pebble.Ui.drawVectorAt"],
      "vector_sequence_at" => ["Pebble.Ui.drawVectorSequenceAt"],
      "arc" => ["Pebble.Ui.arc"],
      "fill_radial" => ["Pebble.Ui.fillRadial"],
      "path_filled" => ["Pebble.Ui.pathFilled"],
      "path_outline" => ["Pebble.Ui.pathOutline"],
      "path_outline_open" => ["Pebble.Ui.pathOutlineOpen"],
      "stroke_color" => ["Pebble.Ui.strokeColor"],
      "fill_color" => ["Pebble.Ui.fillColor"],
      "text_color" => ["Pebble.Ui.textColor"]
    }
    |> Enum.map(fn {kind, targets} ->
      locations =
        targets
        |> Enum.flat_map(&source_locations_for_target(&1, api_metadata))
        |> Enum.uniq_by(&{Map.get(&1, "path"), Map.get(&1, "line"), Map.get(&1, "call")})
        |> Enum.sort_by(&Map.get(&1, "line", 0))

      {kind, locations}
    end)
    |> Enum.reject(fn {_kind, locations} -> locations == [] end)
    |> Map.new()
  end

  def output_source_locations(_api_metadata), do: %{}

  @spec internal_arithmetic_view_type(String.t()) :: String.t()
  # Always use "call" so debugger preview evaluates via the call label (not the
  # operator name as `type`, which previously dropped // and other binops).
  defp internal_arithmetic_view_type(_name), do: "call"

  @spec view_type_name(Types.ast_expr() | String.t()) :: String.t()
  defp view_type_name(target) when is_binary(target) do
    case String.split(target, ".") |> List.last() do
      nil -> target
      last -> last
    end
  end

  @spec put_module_alias(map(), String.t(), String.t()) :: map()
  defp put_module_alias(acc, alias_name, module_name)
       when is_map(acc) and is_binary(alias_name) and is_binary(module_name) and alias_name != "" do
    Map.put(acc, alias_name, module_name)
  end

  defp put_module_alias(acc, _alias_name, _module_name) when is_map(acc), do: acc

  @spec module_short_name(String.t()) :: String.t()
  defp module_short_name(module_name) when is_binary(module_name) do
    module_name |> String.split(".") |> List.last()
  end

  @spec source_call_arg_names(Types.ast_expr() | String.t(), non_neg_integer(), map()) :: [String.t()]
  defp source_call_arg_names(target, arity, api_metadata)
       when is_binary(target) and is_integer(arity) and is_map(api_metadata) do
    case resolve_source_call(target, api_metadata) do
      {module_name, function_name} when is_binary(module_name) and is_binary(function_name) ->
        Map.get(Map.get(api_metadata, :functions, %{}), {module_name, function_name, arity}, [])

      _ ->
        []
    end
  end

  defp source_call_arg_names(_target, _arity, _api_metadata), do: []

  @spec resolve_source_call(String.t(), map()) :: {String.t(), String.t()} | nil
  defp resolve_source_call(target, api_metadata)
       when is_binary(target) and is_map(api_metadata) do
    parts = String.split(target, ".")

    cond do
      length(parts) == 1 ->
        module_name = Map.get(Map.get(api_metadata, :unqualified, %{}), target)
        if is_binary(module_name), do: {module_name, target}, else: nil

      true ->
        resolve_qualified_source_call(parts, api_metadata)
    end
  end

  defp resolve_source_call(_target, _api_metadata), do: nil

  @spec resolve_qualified_source_call([String.t()], map()) :: {String.t(), String.t()} | nil
  defp resolve_qualified_source_call(parts, api_metadata)
       when is_list(parts) and is_map(api_metadata) do
    aliases = Map.get(api_metadata, :aliases, %{})

    1..(length(parts) - 1)
    |> Enum.reverse()
    |> Enum.find_value(fn module_part_count ->
      {module_parts, function_parts} = Enum.split(parts, module_part_count)
      qualifier = Enum.join(module_parts, ".")
      function_name = Enum.join(function_parts, ".")
      module_name = Map.get(aliases, qualifier, qualifier)

      if is_binary(function_name) and function_name != "" do
        {module_name, function_name}
      end
    end)
  end

  @spec view_arg_label(list()) :: String.t()
  defp view_arg_label(args) when is_list(args) do
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
  defp view_arg_snippet(%{op: :int_literal, value: v}), do: Integer.to_string(v)
  defp view_arg_snippet(%{op: :float_literal, value: v}) when is_number(v), do: to_string(v)
  defp view_arg_snippet(%{op: :char_literal, value: v}) when is_binary(v), do: inspect(v)
  defp view_arg_snippet(%{op: :string_literal, value: v}), do: inspect(v)
  defp view_arg_snippet(%{op: :var, name: n}), do: n
  defp view_arg_snippet(%{op: :field_access} = expr), do: field_access_label(expr)
  defp view_arg_snippet(%{op: :list_literal, items: is}), do: "[#{length(is)}]"
  defp view_arg_snippet(_), do: "…"

  @spec field_access_label(Types.ast_expr()) :: String.t()
  defp field_access_label(%{op: :field_access, arg: arg, field: field}) when is_binary(field) do
    case ElmIntrospect.resolve_case_subject_expr(%{op: :field_access, arg: arg, field: field}, %{}) do
      value when is_binary(value) and value != "" -> value
      _ -> field
    end
  end

  defp field_access_label(_), do: "field_access"


  @spec from_view_expr(Types.ast_expr() | nil, Types.view_build_metadata()) :: Types.view_tree()
  def from_view_expr(nil, _api_metadata), do: view_tree_unknown()

  def from_view_expr(expr, api_metadata) when is_map(api_metadata) do
    expr
    |> normalize_view_expr()
    |> expr_to_view_tree(0, 40, api_metadata)
    |> annotate_view_tree_sources(api_metadata)
  end

  @spec unknown() :: Types.view_tree()
  def unknown, do: view_tree_unknown()
end
