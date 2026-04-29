defmodule Ide.Debugger.ElmIntrospect do
  @moduledoc """
  Static Elm source introspection for debugger bootstrap and trigger discovery.
  """

  @dialyzer :no_match

  alias ElmEx.Frontend.GeneratedParser
  alias ElmEx.Frontend.Module

  # Keep in sync with ElmEx.Frontend.GeneratedParser @default_core_imports
  @implicit_core_imports ~w(Basics List Maybe Result String Char Tuple Debug)

  @doc """
  Parses an on-disk Elm module and returns debugger-friendly snapshots derived from the
  elmc frontend AST (static — does not execute Elm).
  """
  @spec analyze_file(Path.t()) :: {:ok, map()} | {:error, term()}
  def analyze_file(path) when is_binary(path) do
    case GeneratedParser.parse_file(path) do
      {:ok, %Module{} = mod} -> {:ok, build_snapshot(mod)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Writes `source` to a temp file, parses it, then deletes the file.
  """
  @spec analyze_source(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def analyze_source(source, virtual_path \\ "Main.elm")
      when is_binary(source) and is_binary(virtual_path) do
    dir = System.tmp_dir!()
    path = Path.join(dir, "ide_elm_introspect_#{:erlang.unique_integer([:positive])}.elm")

    try do
      File.write!(path, source)
      analyze_file(path)
    after
      _ = File.rm(path)
    end
  end

  @spec import_entry_summary(map()) :: String.t()
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

  @spec first_non_nil([term()]) :: term()
  defp first_non_nil(values) when is_list(values) do
    Enum.find(values, &(!is_nil(&1)))
  end

  @spec build_snapshot(Module.t()) :: map()
  defp build_snapshot(%Module{} = mod) do
    init_params = function_param_names(find_function_definition(mod, "init"))
    init_e = find_init_expr(mod)
    init_model = map_expr(init_e, &expr_to_json_value(init_model_expr(&1), 0, 8), nil)

    view_params = function_param_names(find_function_definition(mod, "view"))
    view_e = find_view_expr(mod)
    {view_case_branches, view_case_subject} = view_case_analysis(view_e, view_params)
    api_metadata = source_api_metadata(mod)

    view_tree =
      map_expr(
        view_e,
        &expr_to_view_tree(normalize_view_expr(&1), 0, 40, api_metadata),
        view_tree_unknown()
      )

    update_params = function_param_names(find_function_definition(mod, "update"))
    update_e = find_update_expr(mod)
    {update_branches, update_case_subject} = update_case_analysis(update_e, update_params)

    update_cmd_ops = map_expr(update_e, &update_cmd_ops_outline(&1, update_params), [])

    update_cmd_calls = map_expr(update_e, &update_cmd_calls_outline(&1, update_params), [])

    subscriptions_params =
      function_param_names(find_function_definition(mod, "subscriptions"))

    sub_e = find_subscriptions_expr(mod)

    subscription_ops = map_expr(sub_e, &subscriptions_outline(&1, subscriptions_params), [])

    subscription_calls = map_expr(sub_e, &extract_subscription_calls/1, [])

    main_e = find_main_expr(mod)
    main_program = main_program_outline(main_e)

    init_cmd_ops = map_expr(init_e, &init_cmd_ops_outline(&1, init_params), [])

    init_cmd_calls = map_expr(init_e, &init_cmd_calls_outline(&1, init_params), [])

    {init_case_branches, init_case_subject} =
      scrutinee_case_analysis(init_e, init_params)

    {subscriptions_case_branches, subscriptions_case_subject} =
      scrutinee_case_analysis(sub_e, subscriptions_params)

    {ports, port_module, module_exposing, import_entries, source_byte_size, source_line_count} =
      module_source_scan(mod)

    imported_modules = explicit_imports(mod)
    {type_aliases, unions, functions} = declaration_names(mod)

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
        "view_tree" => view_tree
      }
    }
  end

  @spec map_expr(map() | nil, (map() -> term()), term()) :: term()
  defp map_expr(nil, _fun, fallback), do: fallback
  defp map_expr(%{} = expr, fun, _fallback) when is_function(fun, 1), do: fun.(expr)

  @spec declaration_names(term()) :: term()
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

  @spec explicit_imports(term()) :: term()
  defp explicit_imports(%Module{imports: im}) when is_list(im) do
    im |> Enum.reject(&(&1 in @implicit_core_imports))
  end

  @spec module_source_scan(term()) :: term()
  defp module_source_scan(%Module{} = mod) do
    source_stats =
      case File.read(mod.path) do
        {:ok, source} ->
          {byte_size(source), source_line_count(source)}

        {:error, _} ->
          {nil, nil}
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

  @spec source_line_count(term()) :: term()
  defp source_line_count(source) when is_binary(source) do
    case String.split(source, "\n") do
      [] -> 0
      parts -> length(parts)
    end
  end

  @spec normalize_ports(term()) :: term()
  defp normalize_ports(ports) when is_list(ports) do
    ports
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
  end

  defp normalize_ports(_), do: []

  @spec normalize_exposing(term()) :: term()
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

  @spec normalize_import_entries(term()) :: term()
  defp normalize_import_entries(entries) when is_list(entries) do
    entries
    |> Enum.map(&normalize_import_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_import_entries(_), do: []

  @spec normalize_import_entry(term()) :: term()
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

  @spec find_function_definition(term(), term()) :: term()
  defp find_function_definition(%Module{declarations: decls}, name) when is_binary(name) do
    Enum.find(decls, fn decl ->
      Map.get(decl, :kind) == :function_definition and Map.get(decl, :name) == name
    end)
  end

  @spec function_param_names(term()) :: term()
  defp function_param_names(%{args: args}) when is_list(args), do: args
  defp function_param_names(_), do: []

  @spec find_init_expr(term()) :: term()
  defp find_init_expr(%Module{} = mod) do
    case find_function_definition(mod, "init") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec find_view_expr(term()) :: term()
  defp find_view_expr(%Module{} = mod) do
    case find_function_definition(mod, "view") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec find_update_expr(term()) :: term()
  defp find_update_expr(%Module{} = mod) do
    case find_function_definition(mod, "update") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec find_subscriptions_expr(term()) :: term()
  defp find_subscriptions_expr(%Module{} = mod) do
    case find_function_definition(mod, "subscriptions") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec find_main_expr(term()) :: term()
  defp find_main_expr(%Module{} = mod) do
    case find_function_definition(mod, "main") do
      %{expr: expr} -> expr
      _ -> nil
    end
  end

  @spec main_program_outline(term()) :: term()
  defp main_program_outline(nil), do: nil

  defp main_program_outline(expr) do
    expr
    |> peel_lets()
    |> case do
      %{op: :qualified_call, target: t, args: args} when is_list(args) and args != [] ->
        record_fields =
          case hd(args) do
            %{op: :record_literal, fields: fs} when is_list(fs) ->
              fs
              |> Enum.map(fn %{name: n} -> n end)
              |> Enum.filter(&(is_binary(&1) and &1 != "_invalid"))

            _ ->
              []
          end

        %{
          "target" => t,
          "kind" => main_kind_from_target(t),
          "fields" => record_fields
        }

      _ ->
        nil
    end
  end

  @spec main_kind_from_target(term()) :: term()
  defp main_kind_from_target(t) when is_binary(t) do
    case view_type_name(t) do
      "worker" -> "worker"
      "element" -> "element"
      "document" -> "document"
      "sandbox" -> "sandbox"
      _ -> "unknown"
    end
  end

  @spec init_cmd_ops_outline(term(), term()) :: term()
  defp init_cmd_ops_outline(nil, _), do: []

  defp init_cmd_ops_outline(expr, init_params) when is_list(init_params) do
    allowed = init_case_subjects(init_params)

    {peeled, bindings} = peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches}
      when is_binary(subj) and is_list(branches) ->
        resolved_subj = resolve_case_subject(subj, bindings)

        if init_case_subject_allowed?(resolved_subj, allowed, init_params) do
          Enum.flat_map(branches, fn
            %{expr: e} -> cmd_ops_from_case_branch_expr(e)
            _ -> []
          end)
        else
          []
        end

      %{op: :tuple2, right: right} ->
        right |> peel_lets() |> extract_subscription_items()

      _ ->
        []
    end
  end

  defp init_cmd_ops_outline(_, _), do: []

  @spec init_cmd_calls_outline(term(), term()) :: term()
  defp init_cmd_calls_outline(nil, _), do: []

  defp init_cmd_calls_outline(expr, init_params) when is_list(init_params) do
    allowed = init_case_subjects(init_params)

    {peeled, bindings} = peel_lets_with_bindings(expr)

    calls =
      case peeled do
        %{op: :case, subject: subj, branches: branches}
        when is_binary(subj) and is_list(branches) ->
          resolved_subj = resolve_case_subject(subj, bindings)

          if init_case_subject_allowed?(resolved_subj, allowed, init_params) do
            Enum.flat_map(branches, fn
              %{expr: e} -> cmd_calls_from_case_branch_expr(e)
              _ -> []
            end)
          else
            []
          end

        %{op: :tuple2, right: right} ->
          extract_cmd_calls(right, bindings)

        _ ->
          []
      end

    Enum.uniq_by(calls, &{&1["name"], &1["callback_constructor"], &1["target"]})
  end

  defp init_cmd_calls_outline(_, _), do: []

  @spec update_cmd_ops_outline(term(), term()) :: term()
  defp update_cmd_ops_outline(nil, _), do: []

  defp update_cmd_ops_outline(expr, update_params) when is_list(update_params) do
    allowed = update_case_subjects(update_params)

    expr
    |> peel_update_outer()
    |> case do
      %{op: :case, subject: subj, branches: branches}
      when is_binary(subj) and is_list(branches) ->
        if update_case_subject_allowed?(subj, allowed, update_params) do
          Enum.flat_map(branches, fn
            %{expr: e} -> cmd_ops_from_case_branch_expr(e)
            _ -> []
          end)
        else
          []
        end

      %{op: :tuple2, right: right} ->
        right |> peel_lets() |> extract_subscription_items()

      _ ->
        []
    end
  end

  defp update_cmd_ops_outline(_, _), do: []

  @spec update_cmd_calls_outline(term(), term()) :: term()
  defp update_cmd_calls_outline(nil, _), do: []

  defp update_cmd_calls_outline(expr, update_params) when is_list(update_params) do
    allowed = update_case_subjects(update_params)

    calls =
      expr
      |> peel_update_outer()
      |> case do
        %{op: :case, subject: subj, branches: branches}
        when is_binary(subj) and is_list(branches) ->
          if update_case_subject_allowed?(subj, allowed, update_params) do
            Enum.flat_map(branches, fn
              %{pattern: p, expr: e} ->
                branch_label = pattern_branch_label(p)
                branch_constructor = pattern_constructor_name(p)

                e
                |> cmd_calls_from_case_branch_expr()
                |> Enum.map(fn row ->
                  row
                  |> Map.put("branch", branch_label)
                  |> maybe_put_branch_constructor(branch_constructor)
                end)

              %{expr: e} ->
                cmd_calls_from_case_branch_expr(e)

              _ ->
                []
            end)
          else
            []
          end

        %{op: :tuple2, right: right} ->
          extract_cmd_calls(right)

        _ ->
          []
      end

    Enum.uniq_by(
      calls,
      &{&1["name"], &1["callback_constructor"], &1["target"], &1["branch_constructor"]}
    )
  end

  defp update_cmd_calls_outline(_, _), do: []

  @spec cmd_ops_from_case_branch_expr(term()) :: term()
  defp cmd_ops_from_case_branch_expr(expr) do
    expr
    |> peel_lets()
    |> case do
      %{op: :tuple2, right: right} ->
        right |> peel_lets() |> extract_subscription_items()

      _ ->
        []
    end
  end

  @spec cmd_calls_from_case_branch_expr(term()) :: term()
  defp cmd_calls_from_case_branch_expr(expr) do
    extract_cmd_calls(expr)
  end

  @spec maybe_put_branch_constructor(map(), term()) :: map()
  defp maybe_put_branch_constructor(row, constructor)
       when is_map(row) and is_binary(constructor) and constructor != "" do
    Map.put(row, "branch_constructor", constructor)
  end

  defp maybe_put_branch_constructor(row, _constructor), do: row

  @spec subscriptions_outline(term(), term()) :: term()
  defp subscriptions_outline(nil, _), do: []

  defp subscriptions_outline(expr, subscriptions_params) when is_list(subscriptions_params) do
    allowed = init_case_subjects(subscriptions_params)
    {peeled, bindings} = peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches}
      when is_binary(subj) and is_list(branches) ->
        resolved_subj = resolve_case_subject(subj, bindings)

        if init_case_subject_allowed?(resolved_subj, allowed, subscriptions_params) do
          Enum.flat_map(branches, fn
            %{expr: e} -> e |> peel_lets() |> extract_subscription_items()
            _ -> []
          end)
        else
          extract_subscription_items(peeled)
        end

      _ ->
        extract_subscription_items(peeled)
    end
  end

  defp subscriptions_outline(_, _), do: []

  @spec extract_subscription_items(term()) :: term()
  defp extract_subscription_items(%{
         op: :qualified_call,
         args: [%{op: :list_literal, items: items}]
       })
       when is_list(items) do
    items |> Enum.map(&subscription_item_label/1) |> Enum.reject(&is_nil/1)
  end

  defp extract_subscription_items(%{op: :qualified_call} = qc) do
    case subscription_item_label(qc) do
      nil -> []
      s -> [s]
    end
  end

  defp extract_subscription_items(%{
         op: :call,
         name: name,
         args: [%{op: :list_literal, items: items}]
       })
       when is_list(items) and is_binary(name) do
    items
    |> Enum.map(&subscription_item_label/1)
    |> Enum.reject(&is_nil/1)
    |> then(fn xs -> if xs != [], do: xs, else: [name <> "(…)"] end)
  end

  defp extract_subscription_items(%{op: :list_literal, items: items}) when is_list(items) do
    items |> Enum.map(&subscription_item_label/1) |> Enum.reject(&is_nil/1)
  end

  defp extract_subscription_items(expr) do
    case subscription_item_label(expr) do
      nil -> []
      s -> [s]
    end
  end

  @spec extract_subscription_calls(term()) :: term()
  defp extract_subscription_calls(expr), do: extract_subscription_calls(expr, %{})

  defp extract_subscription_calls(
         %{
           op: :qualified_call,
           target: target,
           args: [%{op: :list_literal, items: items}]
         },
         bindings
       )
       when is_binary(target) and is_list(items) and is_map(bindings) do
    if subscription_batch_target?(target) do
      Enum.flat_map(items, &extract_subscription_calls(&1, bindings))
    else
      subscription_call_rows(target, [%{op: :list_literal, items: items}], bindings)
    end
  end

  defp extract_subscription_calls(
         %{
           op: :qualified_call,
           target: target,
           args: args
         },
         bindings
       )
       when is_binary(target) and is_list(args) and is_map(bindings) do
    subscription_call_rows(target, args, bindings)
  end

  defp extract_subscription_calls(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings
       )
       when is_binary(name) and is_map(bindings) do
    extract_subscription_calls(inner, Map.put(bindings, name, value_expr))
  end

  defp extract_subscription_calls(%{op: :let_in, in_expr: inner}, bindings) when is_map(bindings),
    do: extract_subscription_calls(inner, bindings)

  defp extract_subscription_calls(%{op: :list_literal, items: items}, bindings)
       when is_list(items) and is_map(bindings),
       do: Enum.flat_map(items, &extract_subscription_calls(&1, bindings))

  defp extract_subscription_calls(%{op: :case, branches: branches}, bindings)
       when is_list(branches) and is_map(bindings) do
    Enum.flat_map(branches, fn
      %{expr: expr} -> extract_subscription_calls(expr, bindings)
      _ -> []
    end)
  end

  defp extract_subscription_calls(_, _), do: []

  @spec subscription_call_rows(term(), term(), term()) :: term()
  defp subscription_call_rows(target, args, bindings)
       when is_binary(target) and is_list(args) and is_map(bindings) do
    [
      %{
        "target" => target,
        "name" => view_type_name(target),
        "event_kind" => subscription_event_kind(target),
        "callback_constructor" => callback_constructor_from_args(args, bindings),
        "label" => subscription_item_label(%{op: :qualified_call, target: target, args: args}),
        "arg_kinds" => Enum.map(args, &expr_arg_kind/1)
      }
    ]
  end

  @spec subscription_batch_target?(String.t()) :: boolean()
  defp subscription_batch_target?(target) when is_binary(target) do
    target in ["Sub.batch", "Platform.Sub.batch"] or view_type_name(target) == "batch"
  end

  @spec extract_cmd_calls(term()) :: term()
  defp extract_cmd_calls(expr), do: extract_cmd_calls(expr, %{})

  defp extract_cmd_calls(
         %{
           op: :qualified_call,
           target: "Cmd.batch",
           args: [%{op: :list_literal, items: items}]
         },
         bindings
       )
       when is_list(items) and is_map(bindings) do
    Enum.flat_map(items, &extract_cmd_calls(&1, bindings))
  end

  defp extract_cmd_calls(
         %{
           op: :qualified_call,
           target: target,
           args: args
         },
         bindings
       )
       when is_binary(target) and is_list(args) and is_map(bindings) do
    [
      %{
        "target" => target,
        "name" => view_type_name(target),
        "callback_constructor" => callback_constructor_from_args(args, bindings),
        "arg_kinds" => Enum.map(args, &expr_arg_kind/1)
      }
    ]
  end

  defp extract_cmd_calls(
         %{
           op: :call,
           name: name,
           args: args
         },
         bindings
       )
       when is_binary(name) and is_list(args) and is_map(bindings) do
    [
      %{
        "target" => name,
        "name" => view_type_name(name),
        "callback_constructor" => callback_constructor_from_args(args, bindings),
        "arg_kinds" => Enum.map(args, &expr_arg_kind/1)
      }
    ]
  end

  defp extract_cmd_calls(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings
       )
       when is_binary(name) and is_map(bindings) do
    extract_cmd_calls(inner, Map.put(bindings, name, value_expr))
  end

  defp extract_cmd_calls(%{op: :let_in, in_expr: inner}, bindings) when is_map(bindings),
    do: extract_cmd_calls(inner, bindings)

  defp extract_cmd_calls(%{op: :list_literal, items: items}, bindings)
       when is_list(items) and is_map(bindings),
       do: Enum.flat_map(items, &extract_cmd_calls(&1, bindings))

  defp extract_cmd_calls(%{op: :var, name: name}, bindings)
       when is_binary(name) and is_map(bindings) do
    case Map.get(bindings, name) do
      nil -> []
      expr -> extract_cmd_calls(expr, bindings)
    end
  end

  defp extract_cmd_calls(%{op: :tuple2, right: right}, bindings) when is_map(bindings),
    do: extract_cmd_calls(right, bindings)

  defp extract_cmd_calls(%{op: :case, branches: branches}, bindings)
       when is_list(branches) and is_map(bindings) do
    Enum.flat_map(branches, fn
      %{expr: expr} -> extract_cmd_calls(expr, bindings)
      _ -> []
    end)
  end

  defp extract_cmd_calls(_, _), do: []

  @spec callback_constructor_from_args(term(), term()) :: term()
  defp callback_constructor_from_args(args, bindings)
       when is_list(args) and is_map(bindings) do
    Enum.find_value(args, &callback_constructor_from_expr(&1, bindings, MapSet.new(), 0))
  end

  defp callback_constructor_from_args(_, _), do: nil

  @spec callback_constructor_from_expr(term(), term(), term(), term()) :: term()
  defp callback_constructor_from_expr(_expr, _bindings, _seen, depth) when depth > 10, do: nil

  defp callback_constructor_from_expr(
         %{op: :constructor_call, target: target},
         _bindings,
         _seen,
         _depth
       )
       when is_binary(target),
       do: view_type_name(target)

  defp callback_constructor_from_expr(%{op: :var, name: name}, bindings, seen, depth)
       when is_binary(name) and is_map(bindings) do
    if MapSet.member?(seen, name) do
      nil
    else
      case Map.get(bindings, name) do
        nil -> if(constructor_like_name?(name), do: name, else: nil)
        expr -> callback_constructor_from_expr(expr, bindings, MapSet.put(seen, name), depth + 1)
      end
    end
  end

  defp callback_constructor_from_expr(
         %{op: :record_literal, fields: fields},
         bindings,
         seen,
         depth
       )
       when is_list(fields) do
    expect_expr =
      Enum.find_value(fields, fn
        %{name: "expect", expr: expr} -> expr
        _ -> nil
      end)

    case callback_constructor_from_expr(expect_expr, bindings, seen, depth + 1) do
      nil ->
        Enum.find_value(fields, fn
          %{expr: expr} -> callback_constructor_from_expr(expr, bindings, seen, depth + 1)
          _ -> nil
        end)

      constructor ->
        constructor
    end
  end

  defp callback_constructor_from_expr(%{op: :qualified_call, args: args}, bindings, seen, depth)
       when is_list(args) do
    Enum.find_value(args, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
  end

  defp callback_constructor_from_expr(%{op: :call, args: args}, bindings, seen, depth)
       when is_list(args) do
    Enum.find_value(args, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
  end

  defp callback_constructor_from_expr(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings,
         seen,
         depth
       )
       when is_binary(name) and is_map(bindings) do
    next_bindings = Map.put(bindings, name, value_expr)
    callback_constructor_from_expr(inner, next_bindings, seen, depth + 1)
  end

  defp callback_constructor_from_expr(
         %{op: :tuple2, left: left, right: right},
         bindings,
         seen,
         depth
       ) do
    case callback_constructor_from_expr(left, bindings, seen, depth + 1) do
      nil -> callback_constructor_from_expr(right, bindings, seen, depth + 1)
      constructor -> constructor
    end
  end

  defp callback_constructor_from_expr(%{op: :list_literal, items: items}, bindings, seen, depth)
       when is_list(items) do
    Enum.find_value(items, &callback_constructor_from_expr(&1, bindings, seen, depth + 1))
  end

  defp callback_constructor_from_expr(_, _bindings, _seen, _depth), do: nil

  @spec constructor_like_name?(term()) :: term()
  defp constructor_like_name?(name) when is_binary(name) do
    String.match?(name, ~r/^[A-Z][A-Za-z0-9_]*$/)
  end

  @spec expr_arg_kind(term()) :: term()
  defp expr_arg_kind(%{op: op}) when is_atom(op), do: Atom.to_string(op)
  defp expr_arg_kind(_), do: "unknown"

  @spec subscription_item_label(term()) :: term()
  defp subscription_item_label(%{op: :qualified_call, target: "Cmd.none", args: []}),
    do: "Cmd.none"

  defp subscription_item_label(%{op: :qualified_call, target: "Sub.none", args: []}),
    do: "Sub.none"

  defp subscription_item_label(%{op: :qualified_call, target: t, args: args})
       when is_list(args) do
    fnpart = view_type_name(t)

    parts =
      args
      |> Enum.map(&subscription_arg_snippet/1)
      |> Enum.reject(&(&1 == ""))

    if parts == [], do: fnpart, else: fnpart <> "(" <> Enum.join(parts, ", ") <> ")"
  end

  defp subscription_item_label(%{op: :constructor_call, target: t, args: _}) when is_binary(t) do
    view_type_name(t)
  end

  defp subscription_item_label(%{op: :var, name: n}) when is_binary(n), do: n

  defp subscription_item_label(%{op: :cmd_none}), do: "Cmd.none"

  defp subscription_item_label(_), do: nil

  @spec subscription_event_kind(String.t()) :: String.t()
  defp subscription_event_kind(target) when is_binary(target) do
    target
    |> view_type_name()
    |> String.replace(~r/([a-z])([A-Z])/, "\\1 \\2")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  @spec subscription_arg_snippet(term()) :: term()
  defp subscription_arg_snippet(%{op: :constructor_call, target: t, args: []}) when is_binary(t),
    do: view_type_name(t)

  defp subscription_arg_snippet(%{op: :constructor_call, target: t, args: [_ | _]})
       when is_binary(t),
       do: view_type_name(t) <> "(…)"

  defp subscription_arg_snippet(%{op: :var, name: n}) when is_binary(n), do: n

  defp subscription_arg_snippet(%{op: :int_literal, value: v}), do: Integer.to_string(v)

  defp subscription_arg_snippet(_), do: ""

  @spec init_case_subjects(term()) :: term()
  defp init_case_subjects(init_params) when is_list(init_params) do
    init_params
    |> Enum.filter(&(is_binary(&1) and &1 != "" and &1 != "_"))
    |> Enum.uniq()
  end

  @spec init_case_subject_allowed?(term(), term(), term()) :: term()
  defp init_case_subject_allowed?(subj, allowed, init_params)
       when is_binary(subj) and is_list(allowed) and is_list(init_params) do
    subj in allowed or
      Enum.any?(init_params, fn p ->
        is_binary(p) and p != "_" and p != "" and String.starts_with?(subj, p <> ".")
      end)
  end

  @spec scrutinee_case_analysis(term(), term()) :: term()
  defp scrutinee_case_analysis(nil, _), do: {[], nil}

  defp scrutinee_case_analysis(expr, params) when is_list(params) do
    allowed = init_case_subjects(params)

    {peeled, bindings} = peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches}
      when is_binary(subj) and is_list(branches) ->
        resolved_subj = resolve_case_subject(subj, bindings)

        if init_case_subject_allowed?(resolved_subj, allowed, params) do
          labels =
            Enum.map(branches, fn
              %{pattern: p} -> pattern_branch_label(p)
              _ -> "?"
            end)

          {labels, resolved_subj}
        else
          {[], nil}
        end

      _ ->
        {[], nil}
    end
  end

  defp scrutinee_case_analysis(_, _), do: {[], nil}

  @spec update_case_analysis(term(), term()) :: term()
  defp update_case_analysis(nil, _), do: {[], nil}

  defp update_case_analysis(expr, update_params) when is_list(update_params) do
    allowed = update_case_subjects(update_params)

    {peeled, bindings} = peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches}
      when is_binary(subj) and is_list(branches) ->
        resolved_subj = resolve_case_subject(subj, bindings)

        if update_case_subject_allowed?(resolved_subj, allowed, update_params) do
          labels =
            Enum.map(branches, fn
              %{pattern: p} -> pattern_branch_label(p)
              _ -> "?"
            end)

          {labels, resolved_subj}
        else
          {[], nil}
        end

      _ ->
        {[], nil}
    end
  end

  defp update_case_analysis(_, _), do: {[], nil}

  @spec update_case_subject_allowed?(term(), term(), term()) :: term()
  defp update_case_subject_allowed?(subj, allowed, update_params)
       when is_binary(subj) and is_list(allowed) and is_list(update_params) do
    subj in allowed or
      Enum.any?(update_params, fn p ->
        is_binary(p) and p != "_" and p != "" and String.starts_with?(subj, p <> ".")
      end)
  end

  @spec update_case_subjects(term()) :: term()
  defp update_case_subjects(update_params) when is_list(update_params) do
    base = ["msg", "message"]

    case List.first(update_params) do
      first when is_binary(first) and first != "" and first != "_" ->
        Enum.uniq([first | base])

      _ ->
        base
    end
  end

  @spec view_case_analysis(term(), term()) :: term()
  defp view_case_analysis(nil, _), do: {[], nil}

  defp view_case_analysis(expr, view_params) when is_list(view_params) do
    allowed = view_case_subjects(view_params)

    {peeled, bindings} = peel_lets_with_bindings(expr)

    case peeled do
      %{op: :case, subject: subj, branches: branches}
      when is_binary(subj) and is_list(branches) ->
        resolved_subj = resolve_case_subject(subj, bindings)

        if view_case_subject_allowed?(resolved_subj, allowed, view_params) do
          labels =
            Enum.map(branches, fn
              %{pattern: p} -> pattern_branch_label(p)
              _ -> "?"
            end)

          {labels, resolved_subj}
        else
          {[], nil}
        end

      _ ->
        {[], nil}
    end
  end

  defp view_case_analysis(_, _), do: {[], nil}

  @spec view_case_subjects(term()) :: term()
  defp view_case_subjects(view_params) when is_list(view_params) do
    base = ["model"]

    case List.first(view_params) do
      first when is_binary(first) and first != "" and first != "_" ->
        Enum.uniq([first | base])

      _ ->
        base
    end
  end

  @spec view_case_subject_allowed?(term(), term(), term()) :: term()
  defp view_case_subject_allowed?(subj, allowed, view_params)
       when is_binary(subj) and is_list(allowed) and is_list(view_params) do
    Enum.member?(allowed, subj) or view_case_param_prefix?(subj, List.first(view_params))
  end

  @spec view_case_param_prefix?(String.t(), term()) :: boolean()
  defp view_case_param_prefix?(subj, param) when is_binary(param) and param not in ["", "_"] do
    String.starts_with?(subj, param <> ".")
  end

  defp view_case_param_prefix?(_subj, _param), do: false

  @spec peel_update_outer(term()) :: term()
  defp peel_update_outer(%{op: :let_in, in_expr: inner}), do: peel_update_outer(inner)
  defp peel_update_outer(other), do: other

  @spec peel_lets_with_bindings(term()) :: term()
  defp peel_lets_with_bindings(expr), do: peel_lets_with_bindings(expr, %{})

  defp peel_lets_with_bindings(
         %{op: :let_in, name: name, value_expr: value_expr, in_expr: inner},
         bindings
       )
       when is_binary(name) do
    resolved_value = resolve_case_subject_expr(value_expr, bindings)
    peel_lets_with_bindings(inner, Map.put(bindings, name, resolved_value))
  end

  defp peel_lets_with_bindings(%{op: :let_in, in_expr: inner}, bindings),
    do: peel_lets_with_bindings(inner, bindings)

  defp peel_lets_with_bindings(other, bindings), do: {other, bindings}

  @spec resolve_case_subject(term(), term()) :: term()
  defp resolve_case_subject(subj, bindings) when is_binary(subj) and is_map(bindings) do
    Map.get(bindings, subj, subj)
  end

  defp resolve_case_subject(subj, _), do: subj

  @spec resolve_case_subject_expr(term(), term()) :: term()
  defp resolve_case_subject_expr(%{op: :field_access, arg: arg, field: field}, bindings)
       when is_binary(field) do
    resolved_arg = resolve_case_subject_expr(arg, bindings)

    if is_binary(resolved_arg) and resolved_arg != "" do
      resolved_arg <> "." <> field
    else
      ""
    end
  end

  defp resolve_case_subject_expr(%{op: :var, name: name}, bindings) when is_binary(name) do
    Map.get(bindings, name, name)
  end

  defp resolve_case_subject_expr(arg, _bindings) when is_binary(arg), do: arg
  defp resolve_case_subject_expr(_, _), do: ""

  @spec pattern_branch_label(term()) :: term()
  defp pattern_branch_label(%{kind: :wildcard}), do: "_"

  defp pattern_branch_label(%{kind: :var, name: n}) when is_binary(n), do: n

  defp pattern_branch_label(%{kind: :constructor, name: n, bind: nil, arg_pattern: nil})
       when is_binary(n),
       do: n

  defp pattern_branch_label(%{kind: :constructor, name: n, bind: b, arg_pattern: nil})
       when is_binary(n) and is_binary(b) and b != "",
       do: "#{n} #{b}"

  defp pattern_branch_label(%{kind: :constructor, name: n, arg_pattern: ap})
       when is_binary(n) and not is_nil(ap) do
    inner = pattern_branch_label(ap)
    "#{n} #{inner}"
  end

  defp pattern_branch_label(%{kind: :constructor, name: n}) when is_binary(n), do: n

  defp pattern_branch_label(%{kind: :tuple, elements: els}) when is_list(els) do
    inner = els |> Enum.map(&pattern_branch_label/1) |> Enum.join(", ")
    "(#{inner})"
  end

  defp pattern_branch_label(%{kind: :unknown, source: s}) when is_binary(s),
    do: String.slice(s, 0, 48)

  defp pattern_branch_label(_), do: "?"

  @spec pattern_constructor_name(term()) :: String.t() | nil
  defp pattern_constructor_name(%{kind: :constructor, name: n}) when is_binary(n), do: n
  defp pattern_constructor_name(_), do: nil

  @spec init_model_expr(term()) :: term()
  defp init_model_expr(expr) do
    expr
    |> peel_lets()
    |> case do
      %{op: :tuple2, left: left} ->
        left

      %{op: :case, branches: branches} = case_expr when is_list(branches) ->
        case first_case_branch_init_model(branches) do
          nil -> case_expr
          left -> left
        end

      other ->
        other
    end
  end

  @spec first_case_branch_init_model(term()) :: term()
  defp first_case_branch_init_model(branches) when is_list(branches) do
    Enum.find_value(branches, fn
      %{expr: e} ->
        case peel_lets(e) do
          %{op: :tuple2, left: left} -> left
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  @spec peel_lets(term()) :: term()
  defp peel_lets(%{op: :let_in, in_expr: inner}), do: peel_lets(inner)
  defp peel_lets(other), do: other

  # For view introspection we inline let-bound expressions into var nodes so
  # preview renderers can keep variable names and still derive numeric values.
  @spec normalize_view_expr(term()) :: term()
  defp normalize_view_expr(expr), do: inline_view_lets(expr, %{}, MapSet.new())

  @spec inline_view_lets(term(), term(), term()) :: term()
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

  @spec msg_constructors(term()) :: term()
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

  @spec msg_constructor_arities(term()) :: term()
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

  @spec msg_union(term()) :: term()
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

  @spec expr_to_json_value(term(), term(), term()) :: term()
  defp expr_to_json_value(%{op: :record_literal, fields: fields}, depth, max) when depth < max do
    Enum.into(fields, %{}, fn %{name: n, expr: e} ->
      {n, expr_to_json_value(e, depth + 1, max)}
    end)
  end

  defp expr_to_json_value(%{op: :int_literal, value: v}, _, _), do: v

  defp expr_to_json_value(%{op: :string_literal, value: v}, _, _), do: v

  defp expr_to_json_value(%{op: :char_literal, value: v}, _, _), do: v

  defp expr_to_json_value(%{op: :constructor_call, target: t, args: args}, depth, max)
       when depth < max do
    %{
      "$ctor" => t,
      "$args" => Enum.map(args, &expr_to_json_value(&1, depth + 1, max))
    }
  end

  defp expr_to_json_value(%{op: :qualified_call, target: t, args: args}, depth, max)
       when depth < max do
    %{"$call" => t, "$args" => Enum.map(args, &expr_to_json_value(&1, depth + 1, max))}
  end

  defp expr_to_json_value(%{op: :var, name: n}, _, _), do: %{"$var" => n}

  defp expr_to_json_value(%{op: :cmd_none}, _, _), do: %{"$ctor" => "Cmd.none", "$args" => []}

  defp expr_to_json_value(%{op: :list_literal, items: items}, depth, max) when depth < max do
    Enum.map(items, &expr_to_json_value(&1, depth + 1, max))
  end

  defp expr_to_json_value(%{op: :tuple2, left: l, right: r}, depth, max) when depth < max do
    [expr_to_json_value(l, depth + 1, max), expr_to_json_value(r, depth + 1, max)]
  end

  defp expr_to_json_value(%{op: :unsupported, source: s}, _, _) when is_binary(s) do
    %{"$opaque" => true, "preview" => String.slice(s, 0, 120)}
  end

  defp expr_to_json_value(%{op: op}, _, _), do: %{"$opaque" => true, "op" => to_string(op)}

  defp expr_to_json_value(_, _, _), do: %{"$opaque" => true}

  @spec expr_to_view_tree(term(), term(), term(), map()) :: term()
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
    %{
      "type" => view_type_name(t),
      "qualified_target" => t,
      "label" => view_arg_label(args),
      "arg_names" => source_call_arg_names(t, length(args), api_metadata),
      "children" => Enum.map(args, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
  end

  defp expr_to_view_tree(%{op: :constructor_call, target: t, args: args}, d, max, api_metadata)
       when d < max do
    %{
      "type" => view_type_name(t),
      "qualified_target" => t,
      "label" => view_arg_label(args),
      "arg_names" => source_call_arg_names(t, length(args), api_metadata),
      "children" => Enum.map(args, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
  end

  defp expr_to_view_tree(%{op: :call, name: name, args: args}, d, max, api_metadata)
       when d < max do
    %{
      "type" => "call",
      "label" => name,
      "arg_names" => source_call_arg_names(name, length(args), api_metadata),
      "children" => Enum.map(args, &expr_to_view_tree(&1, d + 1, max, api_metadata))
    }
  end

  defp expr_to_view_tree(%{op: :lambda, body: body}, d, max, api_metadata) when d < max do
    expr_to_view_tree(body, d + 1, max, api_metadata)
  end

  # Let bindings are structural noise for UI shape; keep depth stable.
  defp expr_to_view_tree(%{op: :let_in, in_expr: inner}, d, max, api_metadata) when d < max do
    expr_to_view_tree(inner, d, max, api_metadata)
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

  @spec view_tree_unknown() :: term()
  defp view_tree_unknown, do: %{"type" => "unknown", "label" => "", "children" => []}

  @spec view_type_name(term()) :: term()
  defp view_type_name(target) when is_binary(target) do
    case String.split(target, ".") |> List.last() do
      nil -> target
      last -> last
    end
  end

  @spec source_api_metadata(Module.t()) :: map()
  defp source_api_metadata(%Module{} = mod) do
    entries = normalize_import_entries(Map.get(mod, :import_entries))
    roots = source_roots_for_module(mod)

    modules =
      entries
      |> Enum.map(&Map.get(&1, "module"))
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    function_args =
      modules
      |> Enum.flat_map(fn module_name ->
        case parse_imported_module(module_name, roots) do
          {:ok, imported} -> module_function_args(module_name, imported)
          _ -> []
        end
      end)
      |> Map.new()

    alias_modules =
      entries
      |> Enum.reduce(%{}, fn entry, acc ->
        module_name = Map.get(entry, "module")
        alias_name = Map.get(entry, "as")

        acc
        |> put_module_alias(module_name, module_name)
        |> put_module_alias(alias_name, module_name)
        |> put_module_alias(module_short_name(module_name), module_name)
      end)

    unqualified =
      entries
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

    %{aliases: alias_modules, functions: function_args, unqualified: unqualified}
  end

  @spec source_roots_for_module(Module.t()) :: [String.t()]
  defp source_roots_for_module(%Module{path: path}) when is_binary(path) do
    current_roots =
      path
      |> Path.expand()
      |> Path.dirname()
      |> path_ancestors()

    package_roots =
      [
        Ide.InternalPackages.pebble_elm_src_abs(),
        Ide.InternalPackages.pebble_companion_core_elm_src_abs(),
        Ide.InternalPackages.companion_protocol_elm_src_abs(),
        Ide.InternalPackages.elm_time_elm_src_abs(),
        Ide.InternalPackages.shared_elm_abs(),
        Ide.InternalPackages.shared_elm_companion_abs()
      ]

    (current_roots ++ package_roots)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  @spec path_ancestors(String.t()) :: [String.t()]
  defp path_ancestors(path) when is_binary(path) do
    Stream.unfold(Path.expand(path), fn
      "/" -> nil
      current -> {current, Path.dirname(current)}
    end)
    |> Enum.take(12)
  end

  @spec parse_imported_module(String.t(), [String.t()]) :: {:ok, Module.t()} | :error
  defp parse_imported_module(module_name, roots)
       when is_binary(module_name) and is_list(roots) do
    roots
    |> Enum.map(&Path.join(&1, module_file_path(module_name)))
    |> Enum.find(&File.exists?/1)
    |> case do
      nil ->
        :error

      path ->
        case GeneratedParser.parse_file(path) do
          {:ok, %Module{} = mod} -> {:ok, mod}
          _ -> :error
        end
    end
  end

  defp parse_imported_module(_module_name, _roots), do: :error

  @spec module_file_path(String.t()) :: String.t()
  defp module_file_path(module_name) when is_binary(module_name) do
    module_name
    |> String.split(".")
    |> Path.join()
    |> Kernel.<>(".elm")
  end

  @spec module_function_args(String.t(), Module.t()) :: [
          {{String.t(), String.t(), non_neg_integer()}, [String.t()]}
        ]
  defp module_function_args(module_name, %Module{declarations: declarations})
       when is_binary(module_name) and is_list(declarations) do
    declarations
    |> Enum.flat_map(fn
      %{kind: kind, name: name} = declaration
      when kind in [:function_definition, :function_signature] and is_binary(name) ->
        args = function_param_names(declaration)
        if args == [], do: [], else: [{{module_name, name, length(args)}, args}]

      _ ->
        []
    end)
  end

  @spec put_module_alias(map(), term(), term()) :: map()
  defp put_module_alias(acc, alias_name, module_name)
       when is_map(acc) and is_binary(alias_name) and is_binary(module_name) and alias_name != "" do
    Map.put(acc, alias_name, module_name)
  end

  defp put_module_alias(acc, _alias_name, _module_name) when is_map(acc), do: acc

  @spec module_short_name(term()) :: String.t() | nil
  defp module_short_name(module_name) when is_binary(module_name) do
    module_name |> String.split(".") |> List.last()
  end

  defp module_short_name(_), do: nil

  @spec source_call_arg_names(term(), non_neg_integer(), map()) :: [String.t()]
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

  @spec view_arg_label(term()) :: term()
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

  @spec view_arg_snippet(term()) :: term()
  defp view_arg_snippet(%{op: :int_literal, value: v}), do: Integer.to_string(v)
  defp view_arg_snippet(%{op: :float_literal, value: v}) when is_number(v), do: to_string(v)
  defp view_arg_snippet(%{op: :char_literal, value: v}) when is_binary(v), do: inspect(v)
  defp view_arg_snippet(%{op: :string_literal, value: v}), do: inspect(v)
  defp view_arg_snippet(%{op: :var, name: n}), do: n
  defp view_arg_snippet(%{op: :field_access} = expr), do: field_access_label(expr)
  defp view_arg_snippet(%{op: :list_literal, items: is}), do: "[#{length(is)}]"
  defp view_arg_snippet(_), do: "…"

  @spec field_access_label(term()) :: term()
  defp field_access_label(%{op: :field_access, arg: arg, field: field}) when is_binary(field) do
    case resolve_case_subject_expr(%{op: :field_access, arg: arg, field: field}, %{}) do
      value when is_binary(value) and value != "" -> value
      _ -> field
    end
  end

  defp field_access_label(_), do: "field_access"
end
