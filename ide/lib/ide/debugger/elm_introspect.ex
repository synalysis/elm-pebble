defmodule Ide.Debugger.ElmIntrospect do
  @moduledoc """
  Static Elm source introspection for debugger bootstrap and trigger discovery.
  """

  @dialyzer :no_match

  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Module
  alias Ide.Debugger.ElmIntrospect.EffectAnalysis
  alias Ide.Debugger.ElmIntrospect.SourceIndex
  alias Ide.Debugger.ElmIntrospect.Types
  alias Ide.Debugger.ElmIntrospect.ViewTree

  # Keep in sync with ElmEx.Frontend.GeneratedParser @default_core_imports
  @implicit_core_imports ~w(Basics List Maybe Result String Char Tuple Debug)

  @doc """
  Parses an on-disk Elm module and returns debugger-friendly snapshots derived from the
  elmc frontend AST (static — does not execute Elm).
  """
  @spec analyze_file(Path.t()) :: {:ok, Types.introspect_snapshot()} | {:error, Types.parse_error()}
  def analyze_file(path) when is_binary(path) do
    case GeneratedParser.parse_file(path) do
      {:ok, %Module{} = mod} -> {:ok, build_snapshot(mod)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Parses in-memory Elm `source` using the virtual path for module name resolution.
  """
  @spec analyze_source(String.t(), String.t()) :: {:ok, Types.introspect_snapshot()} | {:error, Types.parse_error()}
  def analyze_source(source, virtual_path \\ "Main.elm")
      when is_binary(source) and is_binary(virtual_path) do
    case GeneratedParser.parse_source(virtual_path, source) do
      {:ok, %Module{} = mod} ->
        {:ok, build_snapshot(mod, source_display_path(virtual_path), source)}

      {:error, _} = err ->
        err
    end
  end

  @spec import_entry_summary(Types.import_entry() | map()) :: String.t()
  def import_entry_summary(%{} = e) do
    m = first_non_nil([Map.get(e, "module"), Map.get(e, :module), "?"])
    a = first_non_nil([Map.get(e, "as"), Map.get(e, :as)])
    x = first_non_nil([Map.get(e, "exposing"), Map.get(e, :exposing)])

    s = m
    s = if is_binary(a) and a != "", do: s <> " as " <> a, else: s

    s <>
      case x do
        ".." ->
          " (..)"

        xs when is_list(xs) and xs != [] ->
          inner =
            xs
            |> Enum.take(3)
            |> Enum.join(",")

          suf = if length(xs) > 3, do: "…", else: ""
          " (" <> inner <> suf <> ")"

        _ ->
          ""
      end
  end

  def import_entry_summary(_), do: "?"

  @spec first_non_nil([Types.wire_pick()]) :: Types.wire_pick()
  defp first_non_nil(values) when is_list(values) do
    Enum.find(values, &(!is_nil(&1)))
  end

  @spec build_snapshot(Module.t(), String.t() | nil, String.t() | nil) :: Types.introspect_snapshot()
  defp build_snapshot(%Module{} = mod, source_path_override \\ nil, source_text_override \\ nil) do
    init_params = function_param_names(find_function_definition(mod, "init"))
    init_e = find_init_expr(mod)
    init_model = map_expr(init_e, &EffectAnalysis.init_model_value(&1, mod), nil)

    view_params = function_param_names(find_function_definition(mod, "view"))
    view_e = find_view_expr(mod)
    {view_case_branches, view_case_subject} = ViewTree.case_analysis(view_e, view_params)

    import_entries = normalize_import_entries(Map.get(mod, :import_entries))
    function_types = SourceIndex.function_type_index(mod, import_entries)

    api_metadata =
      mod
      |> SourceIndex.api_metadata(import_entries)
      |> Map.put(:source_path, source_path_override || source_display_path(mod))
      |> Map.put(:source_lines, source_lines(mod, source_text_override))
      |> Map.put(:module, mod.name)
      |> Map.put(:module_ref, mod)
      |> Map.put(:function_types, function_types)

    view_tree = ViewTree.from_view_expr(view_e, api_metadata)

    view_source_locations = ViewTree.output_source_locations(api_metadata)
    view_return_type = function_return_type(find_function_declaration(mod, "view"))
    function_view_trees = ViewTree.function_render_trees(mod, api_metadata)

    update_params = function_param_names(find_function_declaration(mod, "update"))
    update_e = find_update_expr(mod)
    {update_branches, update_case_subject} =
      EffectAnalysis.update_case_analysis(update_e, update_params)

    update_cmd_ops =
      map_expr(update_e, &EffectAnalysis.update_cmd_ops_outline(&1, update_params), [])

    update_cmd_calls =
      map_expr(update_e, &EffectAnalysis.update_cmd_calls_outline(&1, update_params), [])

    subscriptions_params =
      function_param_names(find_function_definition(mod, "subscriptions"))

    sub_e = find_subscriptions_expr(mod)

    subscription_ops =
      map_expr(sub_e, &EffectAnalysis.subscriptions_outline(&1, subscriptions_params), [])

    subscription_calls =
      map_expr(sub_e, &EffectAnalysis.extract_subscription_calls(&1, subscriptions_params), [])

    main_e = find_main_expr(mod)
    main_program = EffectAnalysis.main_program_outline(main_e)

    init_cmd_ops = map_expr(init_e, &EffectAnalysis.init_cmd_ops_outline(&1, init_params), [])

    init_cmd_calls =
      map_expr(init_e, &EffectAnalysis.init_cmd_calls_outline(&1, init_params), [])

    {init_case_branches, init_case_subject} =
      EffectAnalysis.scrutinee_case_analysis(init_e, init_params)

    {subscriptions_case_branches, subscriptions_case_subject} =
      EffectAnalysis.scrutinee_case_analysis(sub_e, subscriptions_params)

    {ports, port_module, module_exposing, import_entries, source_byte_size, source_line_count} =
      module_source_scan(mod, source_text_override)

    imported_modules = explicit_imports(mod)
    {type_aliases, unions, functions} = declaration_names(mod)
    function_cmd_calls = EffectAnalysis.function_cmd_calls(mod)

    %{
      "elm_introspect" => %{
        "source" => "elmc_parser",
        "source_byte_size" => source_byte_size,
        "source_line_count" => source_line_count,
        "module" => mod.name,
        "module_exposing" => module_exposing,
        "imported_modules" => imported_modules,
        "import_entries" => import_entries,
        "type_aliases" => type_aliases,
        "unions" => unions,
        "functions" => functions,
        "function_cmd_calls" => function_cmd_calls,
        "init_model" => init_model,
        "init_case_branches" => init_case_branches,
        "init_case_subject" => init_case_subject,
        "init_cmd_ops" => init_cmd_ops,
        "init_cmd_calls" => init_cmd_calls,
        "init_params" => init_params,
        "msg_constructors" => msg_constructors(mod),
        "msg_constructor_arities" => msg_constructor_arities(mod),
        "update_case_branches" => update_branches,
        "update_case_subject" => update_case_subject,
        "update_cmd_ops" => update_cmd_ops,
        "update_cmd_calls" => update_cmd_calls,
        "update_params" => update_params,
        "subscription_ops" => subscription_ops,
        "subscription_calls" => subscription_calls,
        "subscriptions_case_branches" => subscriptions_case_branches,
        "subscriptions_case_subject" => subscriptions_case_subject,
        "subscriptions_params" => subscriptions_params,
        "view_params" => view_params,
        "view_case_branches" => view_case_branches,
        "view_case_subject" => view_case_subject,
        "main_program" => main_program,
        "ports" => ports,
        "port_module" => port_module,
        "view_tree" => view_tree,
        "view_source_locations" => view_source_locations,
        "view_return_type" => view_return_type,
        "function_types" => function_types,
        "function_view_trees" => function_view_trees
      }
    }
  end

  @doc """
  Returns true when a parser-derived view tree root still needs runtime Core IR evaluation.
  """
  defdelegate parser_expression_view?(introspect), to: ViewTree

  @doc """
  Returns true when a parser-derived view tree node is still an unevaluated view expression.
  """
  defdelegate parser_expression_view_tree_node?(node, ei), to: ViewTree

  @doc false
  defdelegate runtime_drawable_view_root_type?(type), to: ViewTree

  @doc false
  defdelegate ui_node_type_signature?(type), to: ViewTree

  @doc false
  defdelegate parser_expression_combinator_type?(type, introspect), to: ViewTree

  @doc false
  defdelegate parser_expression_structural_type?(type), to: ViewTree

  @spec map_expr(Types.ast_expr() | nil, (Types.ast_expr() -> term()), term()) :: term()
  defp map_expr(nil, _fun, fallback), do: fallback
  defp map_expr(%{} = expr, fun, _fallback) when is_function(fun, 1), do: fun.(expr)

  @spec declaration_names(Types.module_ref()) :: Types.declaration_names()
  defp declaration_names(%Module{declarations: decls}) when is_list(decls) do
    type_aliases =
      decls
      |> Enum.filter(&match?(%{kind: :type_alias}, &1))
      |> Enum.map(&Map.get(&1, :name))
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    unions =
      decls
      |> Enum.filter(&match?(%{kind: :union}, &1))
      |> Enum.map(&Map.get(&1, :name))
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    functions =
      decls
      |> Enum.filter(&match?(%{kind: :function_definition}, &1))
      |> Enum.map(&Map.get(&1, :name))
      |> Enum.filter(&(is_binary(&1) and &1 != ""))

    {type_aliases, unions, functions}
  end

  @spec explicit_imports(Types.module_ref()) :: [String.t()]
  defp explicit_imports(%Module{imports: im}) when is_list(im) do
    im |> Enum.reject(&(&1 in @implicit_core_imports))
  end

  @spec module_source_scan(Types.module_ref(), String.t() | nil) :: Types.module_scan()
  defp module_source_scan(%Module{} = mod, source_text_override) do
    source_stats =
      cond do
        is_binary(source_text_override) ->
          {byte_size(source_text_override), source_line_count(source_text_override)}

        true ->
          case File.read(mod.path) do
            {:ok, source} ->
              {byte_size(source), source_line_count(source)}

            {:error, _} ->
              {nil, nil}
          end
      end

    {source_byte_size, source_line_count} = source_stats

    {
      normalize_ports(Map.get(mod, :ports)),
      Map.get(mod, :port_module) == true,
      normalize_exposing(Map.get(mod, :module_exposing)),
      normalize_import_entries(Map.get(mod, :import_entries)),
      source_byte_size,
      source_line_count
    }
  end

  @spec source_lines(Module.t(), String.t() | nil) :: [String.t()]
  defp source_lines(%Module{} = mod, source_text_override) do
    source =
      cond do
        is_binary(source_text_override) ->
          source_text_override

        true ->
          case mod do
            %Module{path: path} when is_binary(path) ->
              case File.read(path) do
                {:ok, file_source} -> file_source
                {:error, _} -> nil
              end

            _ ->
              nil
          end
      end

    case source do
      text when is_binary(text) -> String.split(text, "\n", trim: false)
      _ -> []
    end
  end

  @spec source_display_path(Module.t()) :: String.t()
  defp source_display_path(%Module{path: path}) when is_binary(path) do
    source_display_path(path)
  end

  @spec source_display_path(String.t()) :: String.t()
  defp source_display_path(path) when is_binary(path) do
    parts = Path.split(path)

    case Enum.find_index(parts, &(&1 == "src")) do
      index when is_integer(index) ->
        parts
        |> Enum.drop(index)
        |> Path.join()

      _ ->
        Path.basename(path)
    end
  end

  defp source_display_path(_mod), do: nil

  @spec source_line_count(String.t()) :: non_neg_integer()
  defp source_line_count(source) when is_binary(source) do
    case String.split(source, "\n") do
      [] -> 0
      parts -> length(parts)
    end
  end

  @spec normalize_ports([map()] | nil) :: [map()]
  defp normalize_ports(ports) when is_list(ports) do
    ports
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp normalize_ports(_), do: []

  @spec normalize_exposing(Types.exposing_value() | list() | nil) :: Types.exposing_value()
  defp normalize_exposing(".."), do: ".."

  defp normalize_exposing(items) when is_list(items) do
    items
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> nil
      xs -> xs
    end
  end

  defp normalize_exposing(_), do: nil

  @spec normalize_import_entries([Types.import_entry()] | nil) :: [Types.import_entry()]
  defp normalize_import_entries(entries) when is_list(entries) do
    entries
    |> Enum.map(&normalize_import_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_import_entries(_), do: []

  @spec normalize_import_entry(Types.import_entry()) :: Types.import_entry() | nil
  defp normalize_import_entry(%{} = entry) do
    mod = first_non_nil([Map.get(entry, "module"), Map.get(entry, :module)])
    as_name = first_non_nil([Map.get(entry, "as"), Map.get(entry, :as)])

    exposing =
      normalize_exposing(first_non_nil([Map.get(entry, "exposing"), Map.get(entry, :exposing)]))

    if is_binary(mod) and mod != "" do
      %{"module" => mod, "as" => as_name, "exposing" => exposing}
    else
      nil
    end
  end

  defp normalize_import_entry(_), do: nil

  @spec find_function_definition(Types.module_ref(), String.t()) :: Types.ast_declaration() | nil
  def find_function_definition(%Module{declarations: decls}, name) when is_binary(name) do
    Enum.find(decls, fn decl ->
      Map.get(decl, :kind) == :function_definition and Map.get(decl, :name) == name
    end)
  end

  @spec find_function_declaration(Types.module_ref(), String.t()) :: Types.ast_declaration() | nil
  defp find_function_declaration(%Module{declarations: decls}, name) when is_binary(name) do
    Enum.find_value([:function_signature, :function_definition], fn kind ->
      Enum.find(decls, fn decl ->
        Map.get(decl, :kind) == kind and Map.get(decl, :name) == name
      end)
    end)
  end

  @spec function_return_type(Types.ast_declaration() | nil) :: String.t() | nil
  defp function_return_type(%{type: type}) when is_binary(type), do: return_type_from_signature(type)
  defp function_return_type(_), do: nil

  @spec return_type_from_signature(String.t()) :: String.t()
  defp return_type_from_signature(type) when is_binary(type) do
    type
    |> String.split("->")
    |> List.last()
    |> to_string()
    |> String.trim()
  end


  @spec function_param_names(Types.ast_declaration() | map()) :: [String.t()]
  defp function_param_names(%{args: args}) when is_list(args), do: args
  defp function_param_names(_), do: []

  @spec find_init_expr(Types.module_ref()) :: Types.ast_expr() | nil
  defp find_init_expr(%Module{} = mod) do
    case find_function_definition(mod, "init") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec find_view_expr(Types.module_ref()) :: Types.ast_expr() | nil
  defp find_view_expr(%Module{} = mod) do
    case find_function_definition(mod, "view") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec find_update_expr(Types.module_ref()) :: Types.ast_expr() | nil
  defp find_update_expr(%Module{} = mod) do
    case find_function_definition(mod, "update") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec find_subscriptions_expr(Types.module_ref()) :: Types.ast_expr() | nil
  defp find_subscriptions_expr(%Module{} = mod) do
    case find_function_definition(mod, "subscriptions") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec find_main_expr(Types.module_ref()) :: Types.ast_expr() | nil
  defp find_main_expr(%Module{} = mod) do
    case find_function_definition(mod, "main") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec peel_lets_with_bindings(Types.ast_expr()) :: {Types.ast_expr(), Types.binding_map()}
  def peel_lets_with_bindings(expr), do: peel_lets_with_bindings(expr, %{})

  def peel_lets_with_bindings(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings
       )
       when is_binary(name) do
    resolved_value = resolve_case_subject_expr(value_expr, bindings)
    peel_lets_with_bindings(inner, Map.put(bindings, name, resolved_value))
  end

  def peel_lets_with_bindings(%{op: :let_in, in_expr: inner}, bindings),
    do: peel_lets_with_bindings(inner, bindings)

  def peel_lets_with_bindings(other, bindings), do: {other, bindings}

  @spec resolve_case_subject(String.t(), Types.binding_map()) :: String.t()
  defp resolve_case_subject(subj, bindings) when is_binary(subj) and is_map(bindings) do
    case Map.get(bindings, subj, subj) do
      value when is_binary(value) -> value
      _ -> subj
    end
  end

  defp resolve_case_subject(subj, _) when is_binary(subj), do: subj
  defp resolve_case_subject(_, _), do: ""

  @spec case_subject_text(Types.case_subject(), Types.binding_map()) :: String.t()
  def case_subject_text(subj, bindings) when is_binary(subj), do: resolve_case_subject(subj, bindings)

  def case_subject_text(subj, bindings) when is_map(subj),
    do: resolve_case_subject_expr(subj, bindings)

  def case_subject_text(_, _), do: ""

  @spec resolve_case_subject_expr(Types.ast_expr(), Types.binding_map()) :: String.t()
  def resolve_case_subject_expr(%{op: :field_access, arg: arg, field: field}, bindings)
       when is_binary(field) do
    resolved_arg = resolve_case_subject_expr(arg, bindings)

    if is_binary(resolved_arg) and resolved_arg != "" do
      resolved_arg <> "." <> field
    else
      ""
    end
  end

  def resolve_case_subject_expr(%{op: :var, name: name}, bindings) when is_binary(name) do
    Map.get(bindings, name, name)
  end

  def resolve_case_subject_expr(arg, _bindings) when is_binary(arg), do: arg
  def resolve_case_subject_expr(_, _), do: ""

  @spec pattern_branch_label(Types.ast_expr()) :: String.t()
  def pattern_branch_label(%{kind: :wildcard}), do: "_"

  def pattern_branch_label(%{kind: :var, name: n}) when is_binary(n), do: n

  def pattern_branch_label(%{kind: :constructor, name: n, bind: nil, arg_pattern: nil})
       when is_binary(n),
       do: n

  def pattern_branch_label(%{kind: :constructor, name: n, bind: b, arg_pattern: nil})
       when is_binary(n) and is_binary(b) and b != "",
       do: "#{n} #{b}"

  def pattern_branch_label(%{kind: :constructor, name: n, arg_pattern: ap})
       when is_binary(n) and not is_nil(ap) do
    inner = pattern_branch_label(ap)
    "#{n} #{inner}"
  end

  def pattern_branch_label(%{kind: :constructor, name: n}) when is_binary(n), do: n

  def pattern_branch_label(%{kind: :tuple, elements: els}) when is_list(els) do
    inner = els |> Enum.map(&pattern_branch_label/1) |> Enum.join(", ")
    "(#{inner})"
  end

  def pattern_branch_label(%{kind: :unknown, source: s}) when is_binary(s),
    do: String.slice(s, 0, 48)

  def pattern_branch_label(_), do: "?"

  # For view introspection we inline let-bound expressions into var nodes so
  # preview renderers can keep variable names and still derive numeric values.

  @spec msg_constructors(%Module{} | nil) :: Types.string_list()
  defp msg_constructors(%Module{declarations: decls}) do
    decls
    |> msg_union()
    |> case do
      %{constructors: ctors} when is_list(ctors) and ctors != [] ->
        Enum.map(ctors, fn %{name: n} -> n end)

      _ ->
        []
    end
  end

  @spec msg_constructor_arities(%Module{} | nil) :: %{optional(String.t()) => non_neg_integer()}
  defp msg_constructor_arities(%Module{declarations: decls}) do
    decls
    |> msg_union()
    |> case do
      %{constructors: ctors} when is_list(ctors) ->
        Map.new(ctors, fn
          %{name: name, arg: nil} -> {name, 0}
          %{name: name, arg: arg} when is_binary(arg) -> {name, 1}
          %{name: name} -> {name, 0}
        end)

      _ ->
        %{}
    end
  end

  @spec msg_union([map()]) :: map() | nil
  defp msg_union(decls) when is_list(decls) do
    msg_unions = Enum.filter(decls, &match?(%{kind: :union, name: "Msg"}, &1))

    case msg_unions do
      [] ->
        Enum.find(decls, &match?(%{kind: :union}, &1))

      [_ | _] ->
        Enum.max_by(msg_unions, fn u ->
          length(first_non_nil([Map.get(u, :constructors), []]))
        end)
    end
  end

  defp msg_union(_), do: nil


end
