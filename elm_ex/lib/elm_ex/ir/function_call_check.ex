defmodule ElmEx.IR.FunctionCallCheck do
  @moduledoc """
  Validates function call sites against declared type signatures without invoking
  the upstream Elm compiler.
  """

  alias ElmEx.Frontend.DefaultImports
  alias ElmEx.Frontend.Types.ImportEntry
  alias ElmEx.IR.ImportResolution
  alias ElmEx.IR.TypeSignature
  alias ElmEx.IR.Types.Diagnostic
  alias ElmEx.IR.Types.Expr
  alias ElmEx.IR.Types.FunctionCallCheck, as: FCC

  @skip_call_prefixes ~w(__)

  @spec collect_project_diagnostics(
          [FCC.frontend_module()],
          FCC.project_module_exports(),
          String.t(),
          [String.t()]
        ) :: [Diagnostic.t()]
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

          call_diags =
            expr_function_call_diagnostics(
              decl.expr,
              import_lookup,
              signature_lookup,
              type_alias_lookup,
              call_context
            )
            |> elem(0)

          return_diags =
            function_return_diagnostics(
              Map.put(decl, :type, decl_type),
              import_lookup,
              signature_lookup,
              type_alias_lookup,
              call_context
            )

          call_diags ++ return_diags
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

  @spec application_module?(FCC.frontend_module(), [String.t()]) :: boolean()
  defp application_module?(%{path: path}, application_roots) when is_binary(path) do
    expanded = Path.expand(path)

    Enum.any?(application_roots, fn root ->
      String.starts_with?(expanded, root <> "/")
    end)
  end

  defp application_module?(_, _), do: false

  @spec relative_module_file(FCC.frontend_module(), String.t()) :: String.t() | nil
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

  @spec build_signature_lookup([FCC.frontend_module()]) :: FCC.signature_lookup()
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

  @spec build_type_alias_lookup([FCC.frontend_module()]) :: FCC.type_alias_lookup()
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
          spec = %{
            fields: fields,
            field_types: Map.get(alias_decl, :field_types, %{})
          }

          [
            {"#{module_name}.#{alias_decl.name}", spec},
            {alias_decl.name, spec}
          ]
        end
      end)
    end)
    |> Map.new()
  end

  @spec build_module_import_lookup(FCC.frontend_module(), FCC.project_module_exports()) ::
          FCC.import_lookup()
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

  @spec signature_type_for(FCC.frontend_module(), String.t() | nil) :: String.t() | nil
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

  @spec binding_types(FCC.function_decl_context()) :: FCC.binding_types()
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
          Expr.t(),
          FCC.import_lookup(),
          FCC.signature_lookup(),
          FCC.type_alias_lookup(),
          FCC.call_context_wire()
        ) :: FCC.diagnostics_result()
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
          [Expr.t()],
          Expr.t(),
          FCC.import_lookup(),
          FCC.signature_lookup(),
          FCC.type_alias_lookup(),
          FCC.call_context_wire()
        ) :: FCC.diagnostics_result()
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
                  inferred =
                    infer_expr_type(
                      arg,
                      import_lookup,
                      signature_lookup,
                      type_alias_lookup,
                      binding_types
                    )

                  if incompatible_types?(
                       expected,
                       inferred,
                       import_lookup,
                       type_alias_lookup,
                       target,
                       arg
                     ) do
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

  @spec function_return_diagnostics(
          FCC.function_decl_context(),
          FCC.import_lookup(),
          FCC.signature_lookup(),
          FCC.type_alias_lookup(),
          FCC.call_context_wire()
        ) :: [Diagnostic.t()]
  defp function_return_diagnostics(
         decl,
         import_lookup,
         signature_lookup,
         type_alias_lookup,
         call_context
       ) do
    with type when is_binary(type) <- Map.get(decl, :type),
         expr when is_map(expr) <- Map.get(decl, :expr),
         expected when is_binary(expected) <- TypeSignature.return_type(type) do
      binding_types = Map.get(call_context, :binding_types, %{})
      module_name = Map.get(call_context, :module_name)
      function_name = Map.get(call_context, :function_name)
      file = Map.get(call_context, :file)
      line = get_in(decl, [:span, :start_line])
      column = get_in(decl, [:span, :start_column])

      {mismatch?, inferred, mismatch_expr, mismatch_expected} =
        return_type_mismatch?(expected, expr, import_lookup, signature_lookup, type_alias_lookup, binding_types)

      if mismatch? do
        message =
          function_return_message(
            mismatch_expected || expected,
            inferred,
            mismatch_expr,
            type_alias_lookup,
            import_lookup,
            signature_lookup,
            binding_types
          )

        [
          diagnostic(
            "error",
            "function_return_type",
            module_name,
            function_name,
            file,
            line,
            column,
            function_name,
            message,
            expected_type: expected,
            inferred_type: inferred
          )
        ]
      else
        []
      end
    else
      _ -> []
    end
  end

  @spec return_type_mismatch?(
          String.t(),
          Expr.t(),
          FCC.import_lookup(),
          FCC.signature_lookup(),
          FCC.type_alias_lookup(),
          FCC.binding_types()
        ) :: {boolean(), String.t() | nil, Expr.t() | nil, String.t() | nil}
  defp return_type_mismatch?(expected, expr, import_lookup, signature_lookup, type_alias_lookup, binding_types) do
    expected_elems = TypeSignature.tuple_element_types(expected)

    case {expected_elems, expr} do
      {elems, %{op: :tuple2, left: left, right: right}} when elems != [] ->
        inferred_elems =
          Enum.map([left, right], fn part ->
            infer_expr_type(part, import_lookup, signature_lookup, type_alias_lookup, binding_types)
          end)

        inferred = "( #{Enum.join(inferred_elems, ", ")} )"

        mismatch? =
          length(elems) != length(inferred_elems) or
            Enum.zip([left, right], elems)
            |> Enum.any?(fn {part, exp} ->
              record_literal_validation_issues(exp, part, import_lookup, signature_lookup,
                type_alias_lookup,
                binding_types
              ) != [] or
                incompatible_types?(
                  exp,
                  infer_expr_type(part, import_lookup, signature_lookup, type_alias_lookup,
                    binding_types
                  ),
                  import_lookup,
                  type_alias_lookup,
                  nil,
                  part
                )
            end)

        mismatch_part =
          Enum.find(Enum.zip([left, right], elems), fn {part, exp} ->
            record_literal_validation_issues(exp, part, import_lookup, signature_lookup,
              type_alias_lookup,
              binding_types
            ) != [] or
              incompatible_types?(
                exp,
                infer_expr_type(part, import_lookup, signature_lookup, type_alias_lookup,
                  binding_types
                ),
                import_lookup,
                type_alias_lookup,
                nil,
                part
              )
          end)

        case mismatch_part do
          {part, exp} -> {mismatch?, inferred, part, exp}
          _ -> {mismatch?, inferred, expr, nil}
        end

      _ ->
        inferred =
          infer_expr_type(expr, import_lookup, signature_lookup, type_alias_lookup, binding_types)

        mismatch? =
          record_literal_validation_issues(expected, expr, import_lookup, signature_lookup,
            type_alias_lookup,
            binding_types
          ) != [] or
            incompatible_types?(expected, inferred, import_lookup, type_alias_lookup, nil, expr)

        {mismatch?, inferred, expr, nil}
    end
  end

  @spec record_literal_validation_issues(
          String.t(),
          Expr.t(),
          FCC.import_lookup(),
          FCC.signature_lookup(),
          FCC.type_alias_lookup(),
          FCC.binding_types()
        ) :: [FCC.record_validation_issue()]
  defp record_literal_validation_issues(
         expected,
         expr,
         import_lookup,
         signature_lookup,
         type_alias_lookup,
         binding_types
       ) do
    with %{op: :record_literal, fields: fields} when is_list(fields) <- expr,
         resolved when is_binary(resolved) <- resolve_type_reference(expected, import_lookup),
         spec when is_map(spec) <- alias_spec(resolved, type_alias_lookup),
         expected_fields when expected_fields != [] <- alias_fields(resolved, type_alias_lookup) do
      expected_set = MapSet.new(expected_fields)
      literal_names = fields |> Enum.map(&Map.get(&1, :name)) |> Enum.filter(&is_binary/1)
      literal_set = MapSet.new(literal_names)
      expected_field_types = alias_field_types(spec)

      extras =
        literal_set
        |> MapSet.difference(expected_set)
        |> Enum.sort()
        |> Enum.map(&{:extra_field, &1})

      missing =
        expected_set
        |> MapSet.difference(literal_set)
        |> Enum.sort()
        |> Enum.map(&{:missing_field, &1})

      field_types =
        Enum.flat_map(fields, fn %{name: name, expr: field_expr} ->
          with true <- MapSet.member?(expected_set, name),
               expected_type when is_binary(expected_type) <- Map.get(expected_field_types, name),
               inferred_type when is_binary(inferred_type) <-
                 infer_expr_type(
                   field_expr,
                   import_lookup,
                   signature_lookup,
                   type_alias_lookup,
                   binding_types
                 ),
               true <-
                 incompatible_types?(
                   expected_type,
                   inferred_type,
                   import_lookup,
                   type_alias_lookup,
                   nil,
                   field_expr
                 ) do
            [{:field_type, name, expected_type, inferred_type}]
          else
            _ -> []
          end
        end)

      if extras != [] or missing != [] do
        extras ++ missing
      else
        extras ++ missing ++ field_types
      end
    else
      _ -> []
    end
  end

  @spec function_return_message(
          String.t(),
          String.t() | nil,
          Expr.t() | nil,
          FCC.type_alias_lookup(),
          FCC.import_lookup(),
          FCC.signature_lookup(),
          FCC.binding_types()
        ) :: String.t()
  defp function_return_message(
         expected,
         inferred,
         expr,
         type_alias_lookup,
         import_lookup,
         signature_lookup,
         binding_types
       ) do
    issues =
      record_literal_validation_issues(
        expected,
        expr,
        import_lookup,
        signature_lookup,
        type_alias_lookup,
        binding_types
      )

    field_type_issues = Enum.filter(issues, &match?({:field_type, _, _, _}, &1))
    extra_issues = Enum.filter(issues, &match?({:extra_field, _}, &1))
    missing_issues = Enum.filter(issues, &match?({:missing_field, _}, &1))

    cond do
      length(field_type_issues) == 1 ->
        {:field_type, name, expected_type, inferred_type} = hd(field_type_issues)
        "The `#{name}` field expects #{expected_type}, but got #{inferred_type}."

      field_type_issues != [] ->
        names =
          field_type_issues
          |> Enum.map(fn {:field_type, name, expected_type, inferred_type} ->
            "`#{name}` expects #{expected_type}, but got #{inferred_type}"
          end)
          |> Enum.join("; ")

        "Record field type mismatches for #{expected}: #{names}."

      length(extra_issues) == 1 ->
        {:extra_field, name} = hd(extra_issues)
        "The `#{name}` field does not belong to type #{expected}."

      extra_issues != [] ->
        names = extra_issues |> Enum.map(fn {:extra_field, name} -> "`#{name}`" end) |> Enum.join(", ")
        "These fields do not belong to type #{expected}: #{names}."

      length(missing_issues) == 1 ->
        {:missing_field, name} = hd(missing_issues)
        "The `#{name}` field is required for type #{expected}."

      missing_issues != [] ->
        names = missing_issues |> Enum.map(fn {:missing_field, name} -> "`#{name}`" end) |> Enum.join(", ")
        "Missing fields for type #{expected}: #{names}."

      true ->
        "Expected return type #{expected}, but got #{inferred || "an incompatible value"}."
    end
  end

  @spec next_call_occurrence(FCC.call_context_wire(), String.t()) ::
          {pos_integer(), FCC.call_context_wire()}
  defp next_call_occurrence(call_context, pattern) when is_binary(pattern) do
    counts = Map.get(call_context, :occurrence_counts, %{})
    occurrence = Map.get(counts, pattern, 0) + 1
    {occurrence, Map.put(call_context, :occurrence_counts, Map.put(counts, pattern, occurrence))}
  end

  @spec call_source_pattern(Expr.t(), String.t()) :: String.t()
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
        ) :: Diagnostic.t()
  defp diagnostic(
         severity,
         code,
         module_name,
         function_name,
         file,
         line,
         column,
         call_target,
         message,
         extra
       ) do
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

  @spec call_site_position(FCC.call_context_wire(), String.t(), pos_integer()) ::
          {integer() | nil, integer() | nil}
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

  @spec call_site_matches_in_source(FCC.call_context_wire(), String.t(), pos_integer(), pos_integer()) ::
          [{pos_integer(), pos_integer()}]
  defp call_site_matches_in_source(%{module_path: path}, pattern, start_line, end_line)
       when is_binary(path) and is_binary(pattern) and is_integer(start_line) and
              is_integer(end_line) do
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

  @spec call_site_position_from_body(FCC.call_context_wire(), String.t(), pos_integer()) ::
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

  @spec skip_call_target?(String.t(), FCC.import_lookup()) :: boolean()
  defp skip_call_target?(target, import_lookup) do
    local_call_names = Map.get(import_lookup, :local_call_names, MapSet.new())
    unqualified = target |> String.split(".") |> List.last()

    Enum.any?(@skip_call_prefixes, &String.starts_with?(target, &1)) or
      (not String.contains?(target, ".") and MapSet.member?(local_call_names, target)) or
      unqualified in ["identity", "always", "never"]
  end

  @spec call_target(Expr.t(), FCC.import_lookup()) :: String.t() | nil
  defp call_target(%{op: :qualified_call, target: target}, import_lookup)
       when is_binary(target) do
    ImportResolution.resolve(target, import_lookup)
  end

  defp call_target(%{op: :call, name: name}, import_lookup) when is_binary(name) do
    ImportResolution.resolve(name, import_lookup)
  end

  defp call_target(_, _), do: nil

  @spec infer_expr_type(
          Expr.t(),
          FCC.import_lookup(),
          FCC.signature_lookup(),
          FCC.type_alias_lookup(),
          FCC.binding_types()
        ) :: String.t() | nil
  defp infer_expr_type(expr, import_lookup, signature_lookup, type_alias_lookup, binding_types)

  defp infer_expr_type(%{op: :int_literal}, _, _, _, _), do: "Int"
  defp infer_expr_type(%{op: :float_literal}, _, _, _, _), do: "Float"
  defp infer_expr_type(%{op: :string_literal}, _, _, _, _), do: "String"
  defp infer_expr_type(%{op: :bool_literal}, _, _, _, _), do: "Bool"
  defp infer_expr_type(%{op: :char_literal}, _, _, _, _), do: "Char"

  defp infer_expr_type(%{op: :var, name: name}, _, _, _, binding_types) when is_binary(name) do
    Map.get(binding_types, name)
  end

  defp infer_expr_type(
         %{op: :field_access, arg: arg, field: field},
         import_lookup,
         signature_lookup,
         type_alias_lookup,
         binding_types
       )
       when is_binary(field) do
    case infer_expr_type(arg, import_lookup, signature_lookup, type_alias_lookup, binding_types) do
      parent_type when is_binary(parent_type) ->
        infer_record_field_type(parent_type, field, import_lookup, type_alias_lookup)

      _ ->
        nil
    end
  end

  defp infer_expr_type(
         %{op: :tuple2, left: left, right: right},
         import_lookup,
         signature_lookup,
         type_alias_lookup,
         binding_types
       ) do
    left_type =
      infer_expr_type(left, import_lookup, signature_lookup, type_alias_lookup, binding_types)

    right_type =
      infer_expr_type(right, import_lookup, signature_lookup, type_alias_lookup, binding_types)

    case {left_type, right_type} do
      {left, right} when is_binary(left) and is_binary(right) ->
        "( #{left}, #{right} )"

      _ ->
        nil
    end
  end

  defp infer_expr_type(%{op: :record_literal, fields: fields}, import_lookup, signature_lookup, type_alias_lookup, binding_types)
       when is_list(fields) do
    inferred_field_types =
      fields
      |> Enum.filter(&(is_binary(Map.get(&1, :name))))
      |> Map.new(fn %{name: name, expr: expr} ->
        {name,
         infer_expr_type(expr, import_lookup, signature_lookup, type_alias_lookup, binding_types)}
      end)

    field_names = inferred_field_types |> Map.keys() |> Enum.sort()

    case find_matching_alias(field_names, type_alias_lookup, inferred_field_types) do
      nil -> record_type_label(field_names)
      alias_name -> alias_name
    end
  end

  defp infer_expr_type(
         %{op: :qualified_call, target: target, args: args},
         import_lookup,
         signature_lookup,
         type_alias_lookup,
         binding_types
       )
       when is_binary(target) and is_list(args) do
    resolved = ImportResolution.resolve(target, import_lookup)

    case Map.get(signature_lookup, resolved) do
      type when is_binary(type) ->
        TypeSignature.return_type(type)

      _ ->
        infer_expr_type(
          %{op: :qualified_call, args: args},
          import_lookup,
          signature_lookup,
          type_alias_lookup,
          binding_types
        )
    end
  end

  defp infer_expr_type(%{op: op, target: target}, import_lookup, signature_lookup, _, _)
       when op in [:qualified_call1, :qualified_call] and is_binary(target) do
    value_type(Map.get(signature_lookup, ImportResolution.resolve(target, import_lookup)))
  end

  defp infer_expr_type(%{op: :call1, name: name}, import_lookup, signature_lookup, _, _)
       when is_binary(name) do
    value_type(Map.get(signature_lookup, ImportResolution.resolve(name, import_lookup)))
  end

  defp infer_expr_type(
         %{op: :call, name: name, args: args},
         import_lookup,
         signature_lookup,
         type_alias_lookup,
         binding_types
       )
       when is_binary(name) and is_list(args) do
    target = ImportResolution.resolve(name, import_lookup)

    case Map.get(signature_lookup, target) do
      type when is_binary(type) ->
        TypeSignature.return_type(type)

      _ ->
        infer_expr_type(
          %{op: :call, args: args},
          import_lookup,
          signature_lookup,
          type_alias_lookup,
          binding_types
        )
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

  @spec find_matching_alias(
          [String.t()],
          FCC.type_alias_lookup(),
          FCC.field_types_map()
        ) :: String.t() | nil
  defp find_matching_alias(field_names, type_alias_lookup, inferred_field_types)
       when is_list(field_names) and is_map(inferred_field_types) do
    candidates =
      type_alias_lookup
      |> Enum.filter(fn {_alias_name, spec} ->
        alias_field_names(spec) == field_names
      end)

    matches =
      if inferred_field_types == %{} do
        candidates
      else
        Enum.filter(candidates, fn {_alias_name, spec} ->
          alias_field_types_compatible?(alias_field_types(spec), inferred_field_types)
        end)
      end

    case matches do
      [{alias_name, _}] -> alias_name
      _ -> nil
    end
  end

  @spec alias_field_names(FCC.type_alias_spec() | [String.t()]) :: [String.t()]
  defp alias_field_names(%{fields: fields}) when is_list(fields), do: Enum.sort(fields)
  defp alias_field_names(fields) when is_list(fields), do: Enum.sort(fields)
  defp alias_field_names(_), do: []

  @spec alias_field_types(FCC.type_alias_spec() | map()) :: FCC.field_types_map()
  defp alias_field_types(%{field_types: field_types}) when is_map(field_types), do: field_types
  defp alias_field_types(_), do: %{}

  @spec infer_record_field_type(
          String.t(),
          String.t(),
          FCC.import_lookup(),
          FCC.type_alias_lookup()
        ) :: String.t() | nil
  defp infer_record_field_type(parent_type, field, import_lookup, type_alias_lookup)
       when is_binary(parent_type) and is_binary(field) do
    resolved = resolve_type_reference(parent_type, import_lookup)

    case alias_spec(resolved, type_alias_lookup) do
      spec when is_map(spec) ->
        case Map.get(alias_field_types(spec), field) do
          type when is_binary(type) -> type
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec alias_field_types_compatible?(FCC.field_types_map(), FCC.field_types_map()) :: boolean()
  defp alias_field_types_compatible?(alias_types, inferred_types)
       when is_map(alias_types) and is_map(inferred_types) do
    Enum.all?(alias_types, fn {field, expected} ->
      case Map.get(inferred_types, field) do
        nil -> true
        inferred -> record_field_types_compatible?(expected, inferred)
      end
    end)
  end

  @spec record_field_types_compatible?(String.t(), String.t()) :: boolean()
  defp record_field_types_compatible?(expected, inferred) do
    normalize_type(expected) == normalize_type(inferred)
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

  @spec incompatible_types?(
          String.t(),
          String.t() | nil,
          FCC.import_lookup(),
          FCC.type_alias_lookup(),
          String.t() | nil,
          Expr.t() | nil
        ) :: boolean()
  defp incompatible_types?(_expected, nil, _import_lookup, _type_alias_lookup, _target, _arg),
    do: false

  defp incompatible_types?(expected, inferred, import_lookup, type_alias_lookup, target, arg) do
    expected = normalize_type(expected)
    inferred = normalize_type(inferred)
    callee_module = callee_module_from_target(target)

    expected_ctx = %{declaring_module: callee_module}
    caller_ctx = import_lookup

    cond do
      expected == inferred ->
        false

      elm_number_literal_coercion?(expected, inferred, arg) ->
        false

      canonical_type_identity(expected, expected_ctx, type_alias_lookup) ==
          canonical_type_identity(inferred, caller_ctx, type_alias_lookup) ->
        false

      TypeSignature.type_variable?(expected) ->
        false

      TypeSignature.type_variable?(inferred) ->
        false

      primitive_type?(expected) and primitive_type?(inferred) ->
        expected != inferred

      TypeSignature.tuple_type?(expected) and TypeSignature.tuple_type?(inferred) ->
        expected_elems = TypeSignature.tuple_element_types(expected)
        inferred_elems = TypeSignature.tuple_element_types(inferred)

        length(expected_elems) != length(inferred_elems) or
          Enum.zip(expected_elems, inferred_elems)
          |> Enum.any?(fn {exp, inf} ->
            incompatible_types?(exp, inf, import_lookup, type_alias_lookup, target, arg)
          end)

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

  # Elm allows integer number literals to satisfy Float parameters (not Int variables).
  @spec elm_number_literal_coercion?(String.t(), String.t(), Expr.t() | nil) :: boolean()
  defp elm_number_literal_coercion?("Float", "Int", arg), do: int_number_literal?(arg)
  defp elm_number_literal_coercion?(_expected, _inferred, _arg), do: false

  @spec int_number_literal?(Expr.t() | nil) :: boolean()
  defp int_number_literal?(%{op: :int_literal}), do: true

  defp int_number_literal?(%{op: op, target: "Basics.negate", args: [inner]})
       when op in [:qualified_call1, :qualified_call],
       do: int_number_literal?(inner)

  defp int_number_literal?(%{op: :call1, name: "negate", args: [inner]}),
    do: int_number_literal?(inner)

  defp int_number_literal?(%{op: :call, name: "negate", args: [inner]}),
    do: int_number_literal?(inner)

  defp int_number_literal?(_), do: false

  @spec callee_module_from_target(String.t() | nil) :: String.t() | nil
  defp callee_module_from_target(target) do
    if is_binary(target) do
      case String.split(target, ".") do
        [_] -> nil
        parts -> parts |> Enum.drop(-1) |> Enum.join(".")
      end
    else
      nil
    end
  end

  @spec canonical_type_identity(String.t(), FCC.type_resolution_context(), FCC.type_alias_lookup()) ::
          String.t()
  defp canonical_type_identity(type, context, type_alias_lookup) do
    type
    |> resolve_type_reference(context)
    |> type_identity_key(type_alias_lookup)
  end

  @spec resolve_type_reference(String.t(), FCC.type_resolution_context()) :: String.t()
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

  @spec split_qualified_type_name(String.t()) ::
          {:qualified, String.t(), String.t()} | {:unqualified, String.t()}
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

  @spec resolve_unqualified_type(String.t(), String.t() | nil, FCC.name_map(), String.t() | nil) ::
          String.t()
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

  @spec match_unqualified_type_export(String.t(), FCC.name_map()) :: String.t() | nil
  defp match_unqualified_type_export(name, type_map) when is_binary(name) and is_map(type_map) do
    case Map.get(type_map, name) do
      module when is_binary(module) -> "#{module}.#{name}"
      _ -> nil
    end
  end

  @spec resolve_module_prefix(String.t(), FCC.name_map()) :: String.t()
  defp resolve_module_prefix(prefix, alias_map) when is_binary(prefix) and is_map(alias_map) do
    case String.split(prefix, ".", parts: 2) do
      [head, rest] ->
        Map.get(alias_map, head, head) <> "." <> rest

      [single] ->
        Map.get(alias_map, single, single)
    end
  end

  @spec type_identity_key(String.t(), FCC.type_alias_lookup()) :: String.t()
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

  @spec normalize_alias_name(String.t(), FCC.type_alias_lookup()) :: String.t()
  defp normalize_alias_name(type, type_alias_lookup) do
    fields = alias_fields(type, type_alias_lookup)
    key = unqualified_type_name(type)

    if fields == [] do
      key
    else
      key <> "{" <> Enum.join(Enum.sort(fields), ",") <> "}"
    end
  end

  @spec alias_type?(String.t(), FCC.type_alias_lookup()) :: boolean()
  defp alias_type?(type, type_alias_lookup) do
    Map.has_key?(type_alias_lookup, type) or
      type
      |> String.split(".")
      |> case do
        [_module, name] -> Map.has_key?(type_alias_lookup, name)
        _ -> false
      end
  end

  @spec alias_compatible_with_record?(String.t(), String.t(), FCC.type_alias_lookup()) :: boolean()
  defp alias_compatible_with_record?(alias_name, record_type, type_alias_lookup) do
    expected_fields = alias_fields(alias_name, type_alias_lookup) |> Enum.sort()
    inferred_fields = record_field_names(record_type, type_alias_lookup) |> Enum.sort()
    expected_fields != [] and expected_fields == inferred_fields
  end

  @spec record_fields_compatible?(String.t(), String.t(), FCC.type_alias_lookup()) :: boolean()
  defp record_fields_compatible?(left, right, type_alias_lookup) do
    left_fields = record_field_names(left, type_alias_lookup) |> Enum.sort()
    right_fields = record_field_names(right, type_alias_lookup) |> Enum.sort()
    left_fields != [] and left_fields == right_fields
  end

  @spec alias_fields(String.t(), FCC.type_alias_lookup()) :: [String.t()]
  defp alias_fields(alias_name, type_alias_lookup) do
    alias_name
    |> alias_spec(type_alias_lookup)
    |> alias_field_names()
  end

  @spec alias_spec(String.t(), FCC.type_alias_lookup()) :: FCC.type_alias_spec() | nil
  defp alias_spec(alias_name, type_alias_lookup) do
    Map.get(type_alias_lookup, alias_name) ||
      case String.split(alias_name, ".", parts: 2) do
        [_module, name] -> Map.get(type_alias_lookup, name)
        _ -> nil
      end
  end

  @spec record_field_names(String.t(), FCC.type_alias_lookup()) :: [String.t()]
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

  @spec ensure_default_import_entries([ImportEntry.wire_map()]) :: [ImportEntry.wire_map()]
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

  @spec build_import_resolution([ImportEntry.wire_map()], FCC.project_module_exports()) ::
          FCC.import_resolution_maps()
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

  @spec maybe_put_alias(FCC.name_map(), String.t() | nil, String.t()) :: FCC.name_map()
  defp maybe_put_alias(acc, alias_name, module_name)
       when is_map(acc) and is_binary(module_name) do
    if is_binary(alias_name) and alias_name != "" do
      Map.put(acc, alias_name, module_name)
    else
      acc
    end
  end

  @spec put_unqualified_name(FCC.name_map(), String.t(), String.t()) :: FCC.name_map()
  defp put_unqualified_name(acc, name, module_name)
       when is_binary(name) and is_binary(module_name) do
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

  @spec register_wildcard_exports(FCC.name_map(), String.t(), FCC.project_module_exports()) ::
          FCC.name_map()
  defp register_wildcard_exports(acc, module_name, project_module_exports)
       when is_map(acc) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      Map.get(project_module_exports, module_name, %{names: [], union_constructors: %{}})

    module_exports
    |> Map.get(:names, [])
    |> Enum.reduce(acc, &put_unqualified_name(&2, &1, module_name))
  end

  @spec register_wildcard_type_exports(FCC.name_map(), String.t(), FCC.project_module_exports()) ::
          FCC.name_map()
  defp register_wildcard_type_exports(acc, module_name, project_module_exports)
       when is_map(acc) and is_binary(module_name) and is_map(project_module_exports) do
    module_exports =
      project_module_exports
      |> Map.get(module_name, %{types: []})

    module_exports
    |> Map.get(:types, [])
    |> Enum.reduce(acc, &put_unqualified_name(&2, &1, module_name))
  end

  @spec expand_import_exposing_names([String.t()], String.t(), FCC.project_module_exports()) ::
          [String.t()]
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

  @spec expand_import_exposing_type_names([String.t()], String.t(), FCC.project_module_exports()) ::
          [String.t()]
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
