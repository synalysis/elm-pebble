defmodule ElmEx.IR.FunctionCallCheck do
  @moduledoc """
  Validates function call sites against declared type signatures without invoking
  the upstream Elm compiler.
  """

  alias ElmEx.Frontend.DefaultImports
  alias ElmEx.IR.TypeSignature

  @typep expr() :: map()
  @typep diagnostic() :: map()

  @skip_call_prefixes ~w(__)

  @spec collect_project_diagnostics([map()], map(), String.t(), [String.t()]) :: [diagnostic()]
  def collect_project_diagnostics(
        frontend_modules,
        project_module_exports,
        project_dir,
        source_directories \\ ["src"]
      )
      when is_list(frontend_modules) and is_map(project_module_exports) and is_binary(project_dir) do
    application_roots = application_source_roots(project_dir, source_directories)
    signature_lookup = build_signature_lookup(frontend_modules)
    type_alias_lookup = build_type_alias_lookup(frontend_modules)

    Enum.flat_map(frontend_modules, fn frontend_module ->
      if application_module?(frontend_module, application_roots) do
        import_lookup = build_module_import_lookup(frontend_module, project_module_exports)

        relative_file = relative_module_file(frontend_module, project_dir)

        frontend_module
        |> Map.get(:declarations, [])
        |> Enum.filter(&(&1.kind == :function_definition and is_map(&1.expr)))
        |> Enum.flat_map(fn decl ->
          decl_type =
            Map.get(decl, :type) ||
              signature_type_for(frontend_module, Map.get(decl, :name))

          call_context = %{
            module_name: Map.get(frontend_module, :name),
            function_name: Map.get(decl, :name),
            file: relative_file,
            module_path: Map.get(frontend_module, :path),
            decl: decl,
            binding_types: binding_types(Map.put(decl, :type, decl_type)),
            occurrence_counts: %{}
          }

          expr_function_call_diagnostics(
            decl.expr,
            import_lookup,
            signature_lookup,
            type_alias_lookup,
            call_context
          )
          |> elem(0)
        end)
      else
        []
      end
    end)
  end

  @spec application_source_roots(String.t(), [String.t()]) :: [String.t()]
  defp application_source_roots(project_dir, source_directories) when is_binary(project_dir) do
    source_directories
    |> List.wrap()
    |> Enum.filter(&(is_binary(&1) and Path.type(&1) == :relative))
    |> Enum.map(&Path.expand(Path.join(project_dir, &1)))
    |> Enum.uniq()
  end

  @spec application_module?(map(), [String.t()]) :: boolean()
  defp application_module?(%{path: path}, application_roots) when is_binary(path) do
    expanded = Path.expand(path)

    Enum.any?(application_roots, fn root ->
      String.starts_with?(expanded, root <> "/")
    end)
  end

  defp application_module?(_, _), do: false

  @spec relative_module_file(map(), String.t()) :: String.t() | nil
  defp relative_module_file(%{path: path}, project_dir)
       when is_binary(path) and is_binary(project_dir) do
    expanded_project = Path.expand(project_dir)
    expanded_path = Path.expand(path)

    if String.starts_with?(expanded_path, expanded_project <> "/") do
      Path.relative_to(expanded_path, expanded_project)
    else
      nil
    end
  end

  defp relative_module_file(%{name: name}, _project_dir) when is_binary(name),
    do: "src/#{name}.elm"

  defp relative_module_file(_, _), do: nil

  @spec build_signature_lookup([map()]) :: %{String.t() => String.t()}
  defp build_signature_lookup(frontend_modules) do
    frontend_modules
    |> Enum.flat_map(fn frontend_module ->
      module_name = Map.get(frontend_module, :name)

      frontend_module
      |> Map.get(:declarations, [])
      |> Enum.filter(&(&1.kind == :function_signature and is_binary(Map.get(&1, :type))))
      |> Enum.map(fn signature ->
        {"#{module_name}.#{signature.name}", String.trim(signature.type)}
      end)
    end)
    |> Map.new()
  end

  @spec build_type_alias_lookup([map()]) :: %{String.t() => [String.t()]}
  defp build_type_alias_lookup(frontend_modules) do
    frontend_modules
    |> Enum.flat_map(fn frontend_module ->
      module_name = Map.get(frontend_module, :name)

      frontend_module
      |> Map.get(:declarations, [])
      |> Enum.filter(&(&1.kind == :type_alias))
      |> Enum.flat_map(fn alias_decl ->
        fields = Map.get(alias_decl, :fields) || []

        if fields == [] do
          []
        else
          [
            {"#{module_name}.#{alias_decl.name}", fields},
            {alias_decl.name, fields}
          ]
        end
      end)
    end)
    |> Map.new()
  end

  @spec build_module_import_lookup(map(), map()) :: map()
  defp build_module_import_lookup(frontend_module, project_module_exports) do
    import_entries =
      frontend_module
      |> Map.get(:import_entries, [])
      |> ensure_default_import_entries()

    {alias_map, import_unqualified_map, _wildcard_modules, type_unqualified_map} =
      build_import_resolution(import_entries, project_module_exports)

    local_call_names =
      frontend_module
      |> Map.get(:declarations, [])
      |> Enum.filter(&(&1.kind == :function_definition))
      |> Enum.map(& &1.name)
      |> MapSet.new()

    %{
      alias_map: alias_map,
      import_unqualified_map: import_unqualified_map,
      type_unqualified_map: type_unqualified_map,
      local_call_names: local_call_names,
      current_module: Map.get(frontend_module, :name)
    }
  end

  @spec signature_type_for(map(), String.t() | nil) :: String.t() | nil
  defp signature_type_for(_frontend_module, nil), do: nil

  defp signature_type_for(frontend_module, name) when is_binary(name) do
    frontend_module
    |> Map.get(:declarations, [])
    |> Enum.find_value(fn decl ->
      if decl.kind == :function_signature and decl.name == name and is_binary(decl.type) do
        decl.type
      end
    end)
  end

  @spec binding_types(map()) :: %{String.t() => String.t()}
  defp binding_types(%{args: args, type: type})
       when is_list(args) and is_binary(type) and args != [] do
    TypeSignature.param_types(type)
    |> Enum.with_index()
    |> Enum.reduce(%{}, fn {param_type, index}, acc ->
      case Enum.at(args, index) do
        arg_name when is_binary(arg_name) -> Map.put(acc, arg_name, param_type)
        _ -> acc
      end
    end)
  end

  defp binding_types(_decl), do: %{}

  @spec expr_function_call_diagnostics(
          expr(),
          map(),
          map(),
          map(),
          map()
        ) :: {[diagnostic()], map()}
  defp expr_function_call_diagnostics(
         %{op: op, args: args} = expr,
         import_lookup,
         signature_lookup,
         type_alias_lookup,
         call_context
       )
       when op in [:call, :qualified_call] and is_list(args) do
    target = call_target(expr, import_lookup)

    {current, call_context} =
      call_site_diagnostics(
        target,
        args,
        expr,
        import_lookup,
        signature_lookup,
        type_alias_lookup,
        call_context
      )

    {nested, call_context} =
      Enum.reduce(args, {[], call_context}, fn arg, {acc, ctx} ->
        if is_map(arg) do
          {child, ctx} =
            expr_function_call_diagnostics(
              arg,
              import_lookup,
              signature_lookup,
              type_alias_lookup,
              ctx
            )

          {acc ++ child, ctx}
        else
          {acc, ctx}
        end
      end)

    {current ++ nested, call_context}
  end

  defp expr_function_call_diagnostics(
         expr,
         import_lookup,
         signature_lookup,
         type_alias_lookup,
         call_context
       )
       when is_map(expr) do
    expr
    |> Map.values()
    |> Enum.reduce({[], call_context}, fn value, {acc, ctx} ->
      cond do
        is_map(value) ->
          {child, ctx} =
            expr_function_call_diagnostics(
              value,
              import_lookup,
              signature_lookup,
              type_alias_lookup,
              ctx
            )

          {acc ++ child, ctx}

        is_list(value) ->
          Enum.reduce(value, {acc, ctx}, fn item, {list_acc, list_ctx} ->
            if is_map(item) do
              {child, next_ctx} =
                expr_function_call_diagnostics(
                  item,
                  import_lookup,
                  signature_lookup,
                  type_alias_lookup,
                  list_ctx
                )

              {list_acc ++ child, next_ctx}
            else
              {list_acc, list_ctx}
            end
          end)

        true ->
          {acc, ctx}
      end
    end)
  end

  defp expr_function_call_diagnostics(
         _expr,
         _import_lookup,
         _signature_lookup,
         _type_alias_lookup,
         call_context
       ),
       do: {[], call_context}

  @spec call_site_diagnostics(
          String.t() | nil,
          [expr()],
          expr(),
          map(),
          map(),
          map(),
          map()
        ) :: {[diagnostic()], map()}
  defp call_site_diagnostics(
         target,
         args,
         call_expr,
         import_lookup,
         signature_lookup,
         type_alias_lookup,
         call_context
       )
       when is_binary(target) and is_list(args) do
    if skip_call_target?(target, import_lookup) do
      {[], call_context}
    else
      case Map.get(signature_lookup, target) do
        type when is_binary(type) ->
          expected_params = TypeSignature.param_types(type)
          expected_arity = length(expected_params)
          argc = length(args)
          pattern = call_source_pattern(call_expr, target)
          {occurrence, call_context} = next_call_occurrence(call_context, pattern)
          {line, column} = call_site_position(call_context, pattern, occurrence)
          module_name = Map.get(call_context, :module_name)
          function_name = Map.get(call_context, :function_name)
          file = Map.get(call_context, :file)
          binding_types = Map.get(call_context, :binding_types, %{})

          arity_diag =
            if argc > expected_arity do
              [
                diagnostic(
                  "error",
                  "function_call_arity",
                  module_name,
                  function_name,
                  file,
                  line,
                  column,
                  target,
                  "#{short_call_name(target)} expects #{expected_arity} argument(s), but was called with #{argc} argument(s).",
                  expected_arity: expected_arity,
                  args_count: argc
                )
              ]
            else
              []
            end

          type_diag =
            Enum.with_index(args)
            |> Enum.flat_map(fn {arg, index} ->
              case Enum.at(expected_params, index) do
                expected when is_binary(expected) ->
                  inferred = infer_expr_type(arg, import_lookup, signature_lookup, type_alias_lookup, binding_types)

                  if incompatible_types?(expected, inferred, import_lookup, type_alias_lookup, target) do
                    [
                      diagnostic(
                        "error",
                        "function_call_type",
                        module_name,
                        function_name,
                        file,
                        line,
                        column,
                        target,
                        "#{short_call_name(target)} expects argument #{index + 1} to be #{expected}, but got #{inferred}.",
                        arg_index: index + 1,
                        expected_type: expected,
                        inferred_type: inferred
                      )
                    ]
                  else
                    []
                  end

                _ ->
                  []
              end
            end)

          {arity_diag ++ type_diag, call_context}

        _ ->
          {[], call_context}
      end
    end
  end

  defp call_site_diagnostics(_, _, _, _, _, _, call_context), do: {[], call_context}

  @spec next_call_occurrence(map(), String.t()) :: {pos_integer(), map()}
  defp next_call_occurrence(call_context, pattern) when is_binary(pattern) do
    counts = Map.get(call_context, :occurrence_counts, %{})
    occurrence = Map.get(counts, pattern, 0) + 1
    {occurrence, Map.put(call_context, :occurrence_counts, Map.put(counts, pattern, occurrence))}
  end

  @spec call_source_pattern(expr(), String.t()) :: String.t()
  defp call_source_pattern(%{op: :qualified_call, target: target}, _resolved)
       when is_binary(target),
       do: target

  defp call_source_pattern(%{op: :call, name: name}, _resolved) when is_binary(name), do: name

  defp call_source_pattern(_expr, resolved_target) when is_binary(resolved_target),
    do: short_call_name(resolved_target)

  @spec diagnostic(
          String.t(),
          String.t(),
          String.t() | nil,
          String.t() | nil,
          String.t() | nil,
          integer() | nil,
          integer() | nil,
          String.t(),
          String.t(),
          keyword()
        ) :: diagnostic()
  defp diagnostic(severity, code, module_name, function_name, file, line, column, call_target, message, extra) do
    %{
      severity: severity,
      source: "lowerer/expression",
      code: code,
      module: module_name,
      function: function_name,
      file: file,
      line: line,
      column: column,
      call_target: call_target,
      message: message
    }
    |> Map.merge(Map.new(extra))
  end

  @spec call_site_position(map(), String.t(), pos_integer()) :: {integer() | nil, integer() | nil}
  defp call_site_position(call_context, pattern, occurrence)
       when is_binary(pattern) and is_integer(occurrence) and occurrence > 0 do
    decl = Map.get(call_context, :decl, %{})
    start_line = get_in(decl, [:span, :start_line]) || 1
    end_line = get_in(decl, [:span, :end_line]) || start_line

    case call_site_matches_in_source(call_context, pattern, start_line, end_line) do
      matches when is_list(matches) ->
        case Enum.at(matches, occurrence - 1) do
          {line, column} -> {line, column}
          _ -> call_site_position_from_body(decl, pattern, occurrence)
        end

      _ ->
        call_site_position_from_body(decl, pattern, occurrence)
    end
  end

  @spec call_site_matches_in_source(map(), String.t(), pos_integer(), pos_integer()) ::
          [ {pos_integer(), pos_integer()}]
  defp call_site_matches_in_source(%{module_path: path}, pattern, start_line, end_line)
       when is_binary(path) and is_binary(pattern) and is_integer(start_line) and is_integer(end_line) do
    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n")
      |> Enum.slice(start_line - 1, max(end_line - start_line + 1, 1))
      |> Enum.with_index(start_line)
      |> Enum.flat_map(fn {line, line_no} ->
        case match_call_pattern(line, pattern) do
          {:ok, column} -> [{line_no, column}]
          :error -> []
        end
      end)
    else
      []
    end
  end

  defp call_site_matches_in_source(_call_context, _pattern, _start_line, _end_line), do: []

  @spec match_call_pattern(String.t(), String.t()) :: {:ok, pos_integer()} | :error
  defp match_call_pattern(line, pattern) when is_binary(line) and is_binary(pattern) do
    escaped = Regex.escape(pattern)
    regex = ~r/#{escaped}(?![A-Za-z0-9_])/

    case Regex.run(regex, line, return: :index) do
      [{start, _len}] -> {:ok, start + 1}
      _ -> :error
    end
  end

  @spec call_site_position_from_body(map(), String.t(), pos_integer()) ::
          {integer() | nil, integer() | nil}
  defp call_site_position_from_body(decl, pattern, occurrence)
       when is_map(decl) and is_binary(pattern) and is_integer(occurrence) and occurrence > 0 do
    body = Map.get(decl, :body) || ""
    start_line = get_in(decl, [:span, :start_line]) || 1

    body
    |> String.split("\n")
    |> Enum.with_index(start_line)
    |> Enum.flat_map(fn {line, line_no} ->
      case match_call_pattern(line, pattern) do
        {:ok, column} -> [{line_no, column}]
        :error -> []
      end
    end)
    |> case do
      matches ->
        case Enum.at(matches, occurrence - 1) do
          {line, column} -> {line, column}
          _ -> {start_line, 1}
        end
    end
  end

  @spec skip_call_target?(String.t(), map()) :: boolean()
  defp skip_call_target?(target, import_lookup) do
    local_call_names = Map.get(import_lookup, :local_call_names, MapSet.new())
    unqualified = target |> String.split(".") |> List.last()

    Enum.any?(@skip_call_prefixes, &String.starts_with?(target, &1)) or
      (not String.contains?(target, ".") and MapSet.member?(local_call_names, target)) or
      unqualified in ["identity", "always", "never"]
  end

  @spec call_target(expr(), map()) :: String.t() | nil
  defp call_target(%{op: :qualified_call, target: target}, import_lookup) when is_binary(target) do
    resolve_name(target, import_lookup)
  end

  defp call_target(%{op: :call, name: name}, import_lookup) when is_binary(name) do
    resolve_name(name, import_lookup)
  end

  defp call_target(_, _), do: nil

  @spec resolve_name(String.t(), map()) :: String.t()
  defp resolve_name(target, import_lookup) when is_binary(target) do
    alias_map = Map.get(import_lookup, :alias_map, %{})
    import_unqualified_map = Map.get(import_lookup, :import_unqualified_map, %{})
    local_call_names = Map.get(import_lookup, :local_call_names, MapSet.new())
    current_module = Map.get(import_lookup, :current_module)

    case String.split(target, ".", parts: 2) do
      [prefix, rest] ->
        case Map.get(alias_map, prefix) do
          nil -> target
          real_module -> "#{real_module}.#{rest}"
        end

      [single] ->
        cond do
          MapSet.member?(local_call_names, single) and is_binary(current_module) ->
            "#{current_module}.#{single}"

          true ->
            case Map.get(import_unqualified_map, single) do
              module when is_binary(module) and module != "" -> "#{module}.#{single}"
              _ -> target
            end
        end

      _ ->
        target
    end
  end

  @spec infer_expr_type(expr(), map(), map(), map(), map()) :: String.t() | nil
  defp infer_expr_type(expr, import_lookup, signature_lookup, type_alias_lookup, binding_types)

  defp infer_expr_type(%{op: :int_literal}, _, _, _, _), do: "Int"
  defp infer_expr_type(%{op: :float_literal}, _, _, _, _), do: "Float"
  defp infer_expr_type(%{op: :string_literal}, _, _, _, _), do: "String"
  defp infer_expr_type(%{op: :bool_literal}, _, _, _, _), do: "Bool"
  defp infer_expr_type(%{op: :char_literal}, _, _, _, _), do: "Char"

  defp infer_expr_type(%{op: :var, name: name}, _, _, _, binding_types) when is_binary(name) do
    Map.get(binding_types, name)
  end

  defp infer_expr_type(%{op: :record_literal, fields: fields}, _, _, type_alias_lookup, _)
       when is_list(fields) do
    field_names =
      fields
      |> Enum.map(&Map.get(&1, :name))
      |> Enum.filter(&is_binary/1)
      |> Enum.sort()

    case find_matching_alias(field_names, type_alias_lookup) do
      nil -> record_type_label(field_names)
      alias_name -> alias_name
    end
  end

  defp infer_expr_type(%{op: op, target: target}, import_lookup, signature_lookup, _, _)
       when op in [:qualified_call1, :qualified_call] and is_binary(target) do
    value_type(Map.get(signature_lookup, resolve_name(target, import_lookup)))
  end

  defp infer_expr_type(%{op: :call1, name: name}, import_lookup, signature_lookup, _, _)
       when is_binary(name) do
    value_type(Map.get(signature_lookup, resolve_name(name, import_lookup)))
  end

  defp infer_expr_type(%{op: :call, name: name, args: args}, import_lookup, signature_lookup, type_alias_lookup, binding_types)
       when is_binary(name) and is_list(args) do
    target = resolve_name(name, import_lookup)

    case Map.get(signature_lookup, target) do
      type when is_binary(type) ->
        TypeSignature.return_type(type)

      _ ->
        infer_expr_type(%{op: :call, args: args}, import_lookup, signature_lookup, type_alias_lookup, binding_types)
    end
  end

  defp infer_expr_type(%{op: :qualified_call, target: target, args: args}, import_lookup, signature_lookup, type_alias_lookup, binding_types)
       when is_binary(target) and is_list(args) do
    resolved = resolve_name(target, import_lookup)

    case Map.get(signature_lookup, resolved) do
      type when is_binary(type) ->
        TypeSignature.return_type(type)

      _ ->
        infer_expr_type(%{op: :qualified_call, args: args}, import_lookup, signature_lookup, type_alias_lookup, binding_types)
    end
  end

  defp infer_expr_type(_, _, _, _, _), do: nil

  @spec value_type(String.t() | nil) :: String.t() | nil
  defp value_type(type) when is_binary(type) do
    case TypeSignature.param_types(type) do
      [] -> String.trim(type)
      _ -> TypeSignature.return_type(type)
    end
  end

  defp value_type(_), do: nil

  @spec find_matching_alias([String.t()], map()) :: String.t() | nil
  defp find_matching_alias(field_names, type_alias_lookup) when is_list(field_names) do
    Enum.find_value(type_alias_lookup, fn {alias_name, alias_fields} ->
      if alias_fields == field_names, do: alias_name
    end)
  end

  @spec record_type_label([String.t()]) :: String.t()
  defp record_type_label(field_names) when is_list(field_names) do
    fields =
      field_names
      |> Enum.map(fn name -> "#{name} : …" end)
      |> Enum.join(", ")

    "{ #{fields} }"
  end

  @primitive_types ~w(Int Float String Bool Char Order)

  @spec incompatible_types?(String.t(), String.t() | nil, map(), map(), String.t() | nil) ::
          boolean()
  defp incompatible_types?(_expected, nil, _import_lookup, _type_alias_lookup, _target), do: false

  defp incompatible_types?(expected, inferred, import_lookup, type_alias_lookup, target) do
    expected = normalize_type(expected)
    inferred = normalize_type(inferred)
    callee_module = callee_module_from_target(target)

    expected_ctx = %{declaring_module: callee_module}
    caller_ctx = import_lookup

    cond do
      expected == inferred -> false
      canonical_type_identity(expected, expected_ctx, type_alias_lookup) ==
          canonical_type_identity(inferred, caller_ctx, type_alias_lookup) ->
        false

      TypeSignature.type_variable?(expected) -> false
      TypeSignature.type_variable?(inferred) -> false
      primitive_type?(expected) and primitive_type?(inferred) -> expected != inferred
      record_type?(expected) and record_type?(inferred) ->
        not record_fields_compatible?(expected, inferred, type_alias_lookup)

      alias_type?(expected, type_alias_lookup) and record_type?(inferred) ->
        not alias_compatible_with_record?(expected, inferred, type_alias_lookup)

      alias_type?(expected, type_alias_lookup) and alias_type?(inferred, type_alias_lookup) ->
        canonical_type_identity(expected, expected_ctx, type_alias_lookup) !=
          canonical_type_identity(inferred, caller_ctx, type_alias_lookup)

      alias_type?(inferred, type_alias_lookup) and primitive_type?(expected) ->
        true

      primitive_type?(expected) and not primitive_type?(inferred) ->
        true

      true ->
        false
    end
  end

  @spec primitive_type?(String.t()) :: boolean()
  defp primitive_type?(type), do: type in @primitive_types

  @spec callee_module_from_target(String.t() | nil) :: String.t() | nil
  defp callee_module_from_target(target) when is_binary(target) do
    case String.split(target, ".") do
      [_] -> nil
      parts -> parts |> Enum.drop(-1) |> Enum.join(".")
    end
  end

  defp callee_module_from_target(_), do: nil

  @spec canonical_type_identity(String.t(), map(), map()) :: String.t()
  defp canonical_type_identity(type, context, type_alias_lookup) do
    type
    |> resolve_type_reference(context)
    |> type_identity_key(type_alias_lookup)
  end

  @spec resolve_type_reference(String.t(), map()) :: String.t()
  defp resolve_type_reference(type, context) when is_binary(type) do
    alias_map = Map.get(context, :alias_map, %{})
    type_map = Map.get(context, :type_unqualified_map, %{})
    declaring_module = Map.get(context, :declaring_module)
    current_module = Map.get(context, :current_module)

    case split_qualified_type_name(type) do
      {:qualified, module_prefix, name} ->
        "#{resolve_module_prefix(module_prefix, alias_map)}.#{name}"

      {:unqualified, name} ->
        resolve_unqualified_type(name, declaring_module, type_map, current_module)
    end
  end

  @spec split_qualified_type_name(String.t()) :: {:qualified, String.t(), String.t()} | {:unqualified, String.t()}
  defp split_qualified_type_name(type) when is_binary(type) do
    case String.split(type, ".") do
      [single] ->
        {:unqualified, single}

      parts ->
        name = List.last(parts)
        module_prefix = parts |> Enum.drop(-1) |> Enum.join(".")
        {:qualified, module_prefix, name}
    end
  end

  @spec resolve_unqualified_type(String.t(), String.t() | nil, map(), String.t() | nil) :: String.t()
  defp resolve_unqualified_type(name, declaring_module, type_map, current_module)
       when is_binary(name) do
    cond do
      is_binary(declaring_module) and declaring_module != "" ->
        "#{declaring_module}.#{name}"

      true ->
        case match_unqualified_type_export(name, type_map) do
          exported when is_binary(exported) ->
            exported

          _ ->
            if is_binary(current_module) and current_module != "" do
              "#{current_module}.#{name}"
            else
              name
            end
        end
    end
  end

  @spec match_unqualified_type_export(String.t(), map()) :: String.t() | nil
  defp match_unqualified_type_export(name, type_map) when is_binary(name) and is_map(type_map) do
    case Map.get(type_map, name) do
      module when is_binary(module) -> "#{module}.#{name}"
      _ -> nil
    end
  end

  @spec resolve_module_prefix(String.t(), map()) :: String.t()
  defp resolve_module_prefix(prefix, alias_map) when is_binary(prefix) and is_map(alias_map) do
    case String.split(prefix, ".", parts: 2) do
      [head, rest] ->
        Map.get(alias_map, head, head) <> "." <> rest

      [single] ->
        Map.get(alias_map, single, single)
    end
  end

  @spec type_identity_key(String.t(), map()) :: String.t()
  defp type_identity_key(resolved, type_alias_lookup) when is_binary(resolved) do
    lookup_name =
      if Map.has_key?(type_alias_lookup, resolved) do
        resolved
      else
        case String.split(resolved, ".", parts: 2) do
          [_module, name] -> name
          _ -> resolved
        end
      end

    normalize_alias_name(lookup_name, type_alias_lookup)
  end

  @spec unqualified_type_name(String.t()) :: String.t()
  defp unqualified_type_name(type) do
    case String.split(type, ".", parts: 2) do
      [_module, name] -> name
      _ -> type
    end
  end

  @spec normalize_alias_name(String.t(), map()) :: String.t()
  defp normalize_alias_name(type, type_alias_lookup) do
    fields = alias_fields(type, type_alias_lookup)
    key = unqualified_type_name(type)

    if fields == [] do
      key
    else
      key <> "{" <> Enum.join(Enum.sort(fields), ",") <> "}"
    end
  end

  @spec alias_type?(String.t(), map()) :: boolean()
  defp alias_type?(type, type_alias_lookup) do
    Map.has_key?(type_alias_lookup, type) or
      type
      |> String.split(".")
      |> case do
        [_module, name] -> Map.has_key?(type_alias_lookup, name)
        _ -> false
      end
  end

  @spec alias_compatible_with_record?(String.t(), String.t(), map()) :: boolean()
  defp alias_compatible_with_record?(alias_name, record_type, type_alias_lookup) do
    expected_fields = alias_fields(alias_name, type_alias_lookup) |> Enum.sort()
    inferred_fields = record_field_names(record_type, type_alias_lookup) |> Enum.sort()
    expected_fields != [] and expected_fields == inferred_fields
  end

  @spec record_fields_compatible?(String.t(), String.t(), map()) :: boolean()
  defp record_fields_compatible?(left, right, type_alias_lookup) do
    left_fields = record_field_names(left, type_alias_lookup) |> Enum.sort()
    right_fields = record_field_names(right, type_alias_lookup) |> Enum.sort()
    left_fields != [] and left_fields == right_fields
  end

  @spec alias_fields(String.t(), map()) :: [String.t()]
  defp alias_fields(alias_name, type_alias_lookup) do
    Map.get(type_alias_lookup, alias_name) ||
      case String.split(alias_name, ".", parts: 2) do
        [_module, name] -> Map.get(type_alias_lookup, name)
        _ -> nil
      end ||
      []
  end

  @spec record_field_names(String.t(), map()) :: [String.t()]
  defp record_field_names(type, type_alias_lookup) do
    cond do
      alias_type?(type, type_alias_lookup) ->
        alias_fields(type, type_alias_lookup)

      TypeSignature.record_type?(type) ->
        TypeSignature.record_field_names(type)

      true ->
        []
    end
  end

  @spec record_type?(String.t()) :: boolean()
  defp record_type?(type), do: TypeSignature.record_type?(type)

  @spec normalize_type(String.t()) :: String.t()
  defp normalize_type(type) do
    type |> String.trim() |> String.replace(~r/\s+/, " ")
  end

  @spec short_call_name(String.t()) :: String.t()
  defp short_call_name(target) do
    target |> String.split(".") |> List.last() |> to_string()
  end

  @spec ensure_default_import_entries([map()]) :: [map()]
  defp ensure_default_import_entries(import_entries) when is_list(import_entries) do
    existing =
      import_entries
      |> Enum.map(&Map.get(&1, "module"))
      |> Enum.filter(&is_binary/1)
      |> MapSet.new()

    default_entries =
      DefaultImports.import_entries()
      |> Enum.reject(fn entry ->
        module_name = Map.get(entry, "module")
        is_binary(module_name) and MapSet.member?(existing, module_name)
      end)

    import_entries ++ default_entries
  end

  @spec build_import_resolution([map()], map()) ::
          {map(), map(), [String.t()], map()}
  defp build_import_resolution(import_entries, project_module_exports)
       when is_list(import_entries) and is_map(project_module_exports) do
    Enum.reduce(import_entries, {%{}, %{}, [], %{}}, fn entry,
                                                        {alias_acc, unqualified_acc, wildcard_acc,
                                                         type_acc} ->
      module_name = Map.get(entry, "module")
      as_name = Map.get(entry, "as")
      exposing = Map.get(entry, "exposing")

      if is_binary(module_name) and module_name != "" do
        segments = String.split(module_name, ".", trim: true)
        compact_name = Enum.join(segments, "")

        alias_acc =
          alias_acc
          |> maybe_put_alias(as_name, module_name)
          |> maybe_put_alias(compact_name, module_name)

        {unqualified_acc, wildcard_acc, type_acc} =
          case exposing do
            ".." ->
              {
                register_wildcard_exports(unqualified_acc, module_name, project_module_exports),
                add_unique_string(wildcard_acc, module_name),
                register_wildcard_type_exports(type_acc, module_name, project_module_exports)
              }

            names when is_list(names) ->
              expanded_names =
                expand_import_exposing_names(names, module_name, project_module_exports)

              exposed_types =
                expand_import_exposing_type_names(names, module_name, project_module_exports)

              mapped =
                expanded_names
                |> Enum.filter(&is_binary/1)
                |> Enum.reduce(unqualified_acc, fn name, acc ->
                  put_unqualified_name(acc, name, module_name)
                end)

              type_mapped =
                exposed_types
                |> Enum.filter(&is_binary/1)
                |> Enum.reduce(type_acc, fn name, acc ->
                  put_unqualified_name(acc, name, module_name)
                end)

              {mapped, wildcard_acc, type_mapped}

            _ ->
              {unqualified_acc, wildcard_acc, type_acc}
          end

        {alias_acc, unqualified_acc, wildcard_acc, type_acc}
      else
        {alias_acc, unqualified_acc, wildcard_acc, type_acc}
      end
    end)
  end

  defp build_import_resolution(_import_entries, _project_module_exports), do: {%{}, %{}, [], %{}}

  @spec maybe_put_alias(map(), String.t() | nil, String.t()) :: map()
  defp maybe_put_alias(acc, alias_name, module_name)
       when is_map(acc) and is_binary(module_name) do
    if is_binary(alias_name) and alias_name != "" do
      Map.put(acc, alias_name, module_name)
    else
      acc
    end
  end

  @spec put_unqualified_name(map(), String.t(), String.t()) :: map()
  defp put_unqualified_name(acc, name, module_name) when is_binary(name) and is_binary(module_name) do
    case Map.get(acc, name) do
      nil -> Map.put(acc, name, module_name)
      ^module_name -> acc
      _other -> Map.put(acc, name, :ambiguous)
    end
  end

  @spec add_unique_string([String.t()], String.t()) :: [String.t()]
  defp add_unique_string(list, value) when is_list(list) and is_binary(value) do
    if value in list, do: list, else: list ++ [value]
  end

  @spec register_wildcard_exports(map(), String.t(), map()) :: map()
  defp register_wildcard_exports(acc, module_name, project_module_exports)
       when is_map(acc) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      Map.get(project_module_exports, module_name, %{names: [], union_constructors: %{}})

    module_exports
    |> Map.get(:names, [])
    |> Enum.reduce(acc, &put_unqualified_name(&2, &1, module_name))
  end

  @spec register_wildcard_type_exports(map(), String.t(), map()) :: map()
  defp register_wildcard_type_exports(acc, module_name, project_module_exports)
       when is_map(acc) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      project_module_exports
      |> Map.get(module_name, %{types: []})

    module_exports
    |> Map.get(:types, [])
    |> Enum.reduce(acc, &put_unqualified_name(&2, &1, module_name))
  end

  @spec expand_import_exposing_names([String.t()], String.t(), map()) :: [String.t()]
  defp expand_import_exposing_names(names, module_name, project_module_exports)
       when is_list(names) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      Map.get(project_module_exports, module_name, %{names: [], union_constructors: %{}})

    union_constructors = Map.get(module_exports, :union_constructors, %{})

    names
    |> Enum.flat_map(fn name ->
      case type_wildcard_name(name) do
        nil ->
          [name]

        type_name ->
          Map.get(union_constructors, type_name, []) ++ [type_name]
      end
    end)
  end

  defp expand_import_exposing_names(_names, _module_name, _project_module_exports), do: []

  @spec expand_import_exposing_type_names([String.t()], String.t(), map()) :: [String.t()]
  defp expand_import_exposing_type_names(names, module_name, project_module_exports)
       when is_list(names) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      Map.get(project_module_exports, module_name, %{types: []})

    exported_types = Map.get(module_exports, :types, [])

    names
    |> Enum.flat_map(fn name ->
      case type_wildcard_name(name) do
        nil -> [name]
        type_name -> [type_name]
      end
    end)
    |> Enum.filter(&(&1 in exported_types))
  end

  defp expand_import_exposing_type_names(_names, _module_name, _project_module_exports), do: []

  @spec type_wildcard_name(String.t()) :: String.t() | nil
  defp type_wildcard_name(name) when is_binary(name) do
    case String.split(name, "(", parts: 2) do
      [type_name, _rest] -> String.trim(type_name)
      _ -> nil
    end
  end
end
