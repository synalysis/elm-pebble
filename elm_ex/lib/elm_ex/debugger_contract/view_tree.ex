defmodule ElmEx.DebuggerContract.ViewTree do
  @moduledoc false

  alias ElmEx.Frontend.Module
  alias ElmEx.DebuggerContract.ViewTree.Operators
  alias ElmEx.DebuggerContract.ViewTree.Structure
  alias ElmEx.DebuggerContract.Types

  @doc """
  Returns true when a parser-derived view tree root still needs runtime Core IR evaluation.
  """
  @spec parser_expression_view?(Types.introspect_snapshot() | Types.elm_introspect()) :: boolean()
  def parser_expression_view?(introspect) when is_map(introspect) do
    ei = ElmEx.DebuggerContract.unwrap_shell(introspect)
    root = Map.get(ei, "view_tree") || %{}
    parser_expression_view_tree_node?(root, ei)
  end

  def parser_expression_view?(_), do: false

  @doc """
  Returns true when a parser-derived view tree node is still an unevaluated view expression.

  Uses declared return types and structural shapes from introspection metadata, not helper names.
  """
  @spec parser_expression_view_tree_node?(Types.view_tree_node(), Types.elm_introspect()) ::
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

  @spec ui_node_call_with_unevaluated_children?(Types.view_tree_node(), Types.elm_introspect()) ::
          boolean()
  defp ui_node_call_with_unevaluated_children?(node, ei) when is_map(node) and is_map(ei) do
    view_tree_call_returns_ui_node?(node, ei) and
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
  @spec parser_expression_combinator_type?(String.t(), Types.elm_introspect()) :: boolean()
  def parser_expression_combinator_type?(type, introspect \\ %{})

  def parser_expression_combinator_type?(type, introspect)
      when is_binary(type) and is_map(introspect) and map_size(introspect) > 0 do
    ei = ElmEx.DebuggerContract.unwrap_shell(introspect)
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
      if Structure.render_op_function_return_type?(signature) do
        case String.split(key, "|", parts: 3) do
          [_module, function_name, _arity] ->
            case ElmEx.DebuggerContract.find_function_definition(mod, function_name) do
              %{expr: expr} when not is_nil(expr) ->
                Map.put(acc, key, Operators.build_view_tree(expr, api_metadata))

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

  @spec view_tree_call_returns_ui_node?(Types.view_tree_node(), Types.elm_introspect()) ::
          boolean()
  defp view_tree_call_returns_ui_node?(node, ei) when is_map(node) and is_map(ei) do
    case Map.get(node, "return_kind") do
      "ui_node" ->
        true

      "render_op" ->
        false

      _ ->
        Structure.view_tree_call_returns_ui_node_from_target?(
          Structure.view_tree_call_target(node),
          Structure.call_tree_arity(node),
          ei
        )
    end
  end

  defp view_tree_call_returns_ui_node?(_, _), do: false

  @spec case_analysis(Types.ast_expr() | nil, Types.param_list()) :: Types.case_branch_labels()
  def case_analysis(nil, _), do: {[], nil}

  def case_analysis(expr, view_params) when is_list(view_params) do
    allowed = view_case_subjects(view_params)

    {peeled, bindings} = ElmEx.DebuggerContract.peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches} when is_list(branches) ->
        if view_case_subject_allowed?(subj, allowed, view_params, bindings) do
          subject_text = ElmEx.DebuggerContract.case_subject_text(subj, bindings)

          labels =
            Enum.map(branches, fn
              %{pattern: p} -> ElmEx.DebuggerContract.pattern_branch_label(p)
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

  @spec view_case_subject_allowed?(
          Types.case_subject(),
          Types.param_list(),
          Types.param_list(),
          Types.binding_map()
        ) ::
          boolean()
  defp view_case_subject_allowed?(subj, allowed, view_params, bindings)
       when is_list(allowed) and is_list(view_params) and is_map(bindings) do
    case ElmEx.DebuggerContract.case_subject_text(subj, bindings) do
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

  @spec view_tree_unknown() :: Types.view_tree()
  def view_tree_unknown, do: %{"type" => "unknown", "label" => "", "children" => []}

  @spec annotate_view_tree_sources(Types.view_tree(), Types.view_build_metadata()) ::
          Types.view_tree()
  def annotate_view_tree_sources(tree, api_metadata)
      when is_map(tree) and is_map(api_metadata) do
    {annotated, _counters} = annotate_view_tree_sources(tree, api_metadata, %{})
    annotated
  end

  def annotate_view_tree_sources(tree, _api_metadata), do: tree

  @spec annotate_view_tree_sources(
          Types.view_tree(),
          Types.view_build_metadata(),
          Types.source_counters()
        ) :: {Types.view_tree(), Types.source_counters()}
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

  @spec view_tree_source_target(Types.view_tree_node()) :: String.t() | nil
  defp view_tree_source_target(%{"qualified_target" => target}) when is_binary(target), do: target
  defp view_tree_source_target(%{qualified_target: target}) when is_binary(target), do: target

  defp view_tree_source_target(%{"type" => "call", "label" => label}) when is_binary(label),
    do: label

  defp view_tree_source_target(%{type: "call", label: label}) when is_binary(label), do: label
  defp view_tree_source_target(_node), do: nil

  @spec maybe_put_view_tree_source(
          Types.view_tree_node(),
          String.t(),
          Types.view_build_metadata(),
          Types.source_counters()
        ) :: Types.view_tree_node()
  defp maybe_put_view_tree_source(node, target, api_metadata, counters) do
    index = Map.get(counters, target, 0)

    case target |> source_locations_for_target(api_metadata) |> source_location_at(index) do
      %{} = source -> Map.put(node, "source", source)
      _ -> node
    end
  end

  @spec increment_source_counter(Types.source_counters(), String.t()) :: Types.source_counters()
  defp increment_source_counter(counters, target) when is_map(counters) and is_binary(target) do
    Map.update(counters, target, 1, &(&1 + 1))
  end

  @spec source_location_at([map()], non_neg_integer()) :: map() | nil
  defp source_location_at([], _index), do: nil

  defp source_location_at(locations, index) when is_list(locations) and is_integer(index) do
    Enum.at(locations, index) || List.last(locations)
  end

  @spec source_locations_for_target(String.t(), Types.view_build_metadata()) ::
          [map()]
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

  @spec source_call_names(String.t(), Types.view_build_metadata()) :: [String.t()]
  defp source_call_names(target, api_metadata) when is_binary(target) and is_map(api_metadata) do
    resolved = Structure.resolve_source_call(target, api_metadata)

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

  @spec output_source_locations(Types.view_build_metadata()) :: Types.output_source_locations()
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
      "bitmap_sequence_at" => ["Pebble.Ui.drawBitmapSequenceAt"],
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

  defdelegate from_view_expr(expr, api_metadata), to: Operators
  defdelegate unknown(), to: Operators
  defdelegate build_view_tree(expr, api_metadata), to: Operators
end
