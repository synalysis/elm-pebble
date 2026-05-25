defmodule ElmEx.CoreIR.Validate do
  @moduledoc false

  alias ElmEx.CoreIR
  alias ElmEx.CoreIR.Types
  alias ElmEx.CoreIR.Types.Expr

  @type shape_error :: %{
          required(:code) => String.t(),
          required(:message) => String.t(),
          required(:path) => [String.t() | integer()],
          optional(:op) => String.t()
        }

  @spec validate_shape(Types.wire_core_ir()) :: {:ok, CoreIR.t()} | {:error, [shape_error()]}
  def validate_shape(%CoreIR{} = core_ir) do
    validate_shape(core_ir_to_map(core_ir))
  end

  def validate_shape(core_ir) when is_map(core_ir) do
    core_ir = normalize_wire_map(core_ir)
    errors = validate_envelope(core_ir, [])

    if errors == [] do
      {:ok,
       %CoreIR{
         version: core_ir["version"],
         modules: core_ir["modules"],
         diagnostics: core_ir["diagnostics"],
         deterministic_sha256:
           core_ir["deterministic_sha256"] || core_ir[:deterministic_sha256] || ""
       }}
    else
      {:error, errors}
    end
  end

  def validate_shape(_), do: {:error, [error(:root, "expected Core IR map or struct", [])]}

  @spec validate_envelope(map(), [String.t() | integer()]) :: [shape_error()]
  defp validate_envelope(core_ir, path) do
    []
    |> maybe_add(validate_version(core_ir, path))
    |> maybe_add(validate_modules(core_ir, path))
    |> maybe_add(validate_diagnostics_list(core_ir, path))
  end

  defp validate_version(%{"version" => "elm_ex.core_ir.v1"}, _path), do: []
  defp validate_version(%{version: "elm_ex.core_ir.v1"}, _path), do: []

  defp validate_version(core_ir, path) do
    [error(:version, "expected version elm_ex.core_ir.v1", path ++ ["version"], op: inspect(Map.get(core_ir, "version") || Map.get(core_ir, :version)))]
  end

  defp validate_modules(%{"modules" => modules}, path) when is_list(modules) do
    Enum.with_index(modules)
    |> Enum.flat_map(fn {mod, idx} ->
      validate_module(mod, path ++ ["modules", idx])
    end)
  end

  defp validate_modules(%{modules: modules}, path) when is_list(modules),
    do: validate_modules(%{"modules" => modules}, path)

  defp validate_modules(_core_ir, path),
    do: [error(:modules, "expected modules list", path ++ ["modules"])]

  defp validate_module(mod, path) when is_map(mod) do
    mod = stringify_keys(mod)

    []
    |> maybe_add(require_key(mod, "name", path))
    |> maybe_add(require_key(mod, "imports", path))
    |> maybe_add(require_key(mod, "unions", path))
    |> maybe_add(require_key(mod, "declarations", path))
    |> maybe_add(validate_declarations(mod["declarations"], path))
  end

  defp validate_module(_, path),
    do: [error(:module, "expected module map", path)]

  defp validate_declarations(decls, path) when is_list(decls) do
    Enum.with_index(decls)
    |> Enum.flat_map(fn {decl, idx} ->
      validate_declaration(decl, path ++ ["declarations", idx])
    end)
  end

  defp validate_declarations(_, path),
    do: [error(:declarations, "expected declarations list", path ++ ["declarations"])]

  defp validate_declaration(decl, path) when is_map(decl) do
    decl = stringify_keys(decl)

    []
    |> maybe_add(require_key(decl, "kind", path))
    |> maybe_add(require_key(decl, "name", path))
    |> maybe_add(require_key(decl, "args", path))
    |> maybe_add(require_key(decl, "ownership", path))
    |> maybe_add(validate_declaration_expr(decl["expr"], path))
  end

  defp validate_declaration(_, path),
    do: [error(:declaration, "expected declaration map", path)]

  defp validate_declaration_expr(nil, _path), do: []
  defp validate_declaration_expr(expr, path), do: validate_expr(expr, path ++ ["expr"])

  defp validate_diagnostics_list(%{"diagnostics" => diagnostics}, path) when is_list(diagnostics) do
    Enum.with_index(diagnostics)
    |> Enum.flat_map(fn {diag, idx} ->
      validate_diagnostic(diag, path ++ ["diagnostics", idx])
    end)
  end

  defp validate_diagnostics_list(%{diagnostics: diagnostics}, path) when is_list(diagnostics),
    do: validate_diagnostics_list(%{"diagnostics" => diagnostics}, path)

  defp validate_diagnostics_list(_core_ir, path),
    do: [error(:diagnostics, "expected diagnostics list", path ++ ["diagnostics"])]

  defp validate_diagnostic(diag, path) when is_map(diag) do
    diag = stringify_keys(diag)

    []
    |> maybe_add(require_key(diag, "severity", path))
    |> maybe_add(require_key(diag, "code", path))
  end

  defp validate_diagnostic(_, path),
    do: [error(:diagnostic, "expected diagnostic map", path)]

  @spec validate_expr(map(), [String.t() | integer()]) :: [shape_error()]
  defp validate_expr(expr, path) when is_map(expr) do
    expr = stringify_keys(expr)

    case normalize_op_name(Map.get(expr, "op") || Map.get(expr, :op)) do
      op when is_binary(op) ->
        validate_expr_op(expr, op, path)

      _ ->
        [error(:expr, ~s(missing or invalid "op"), path, op: inspect(Map.get(expr, "op") || Map.get(expr, :op)))]
    end
  end

  defp validate_expr(_, path),
    do: [error(:expr, "expected expression map", path)]

  defp validate_expr_op(expr, op, path) do
    schema = Expr.required_keys_by_op()

    case Map.fetch(schema, op) do
      {:ok, required} ->
        missing =
          Enum.reject(required, fn key ->
            Map.has_key?(expr, key) and not is_nil(Map.get(expr, key))
          end)

        errors =
          if missing == [] do
            []
          else
            [
              error(
                :invalid_core_ir_shape,
                "expr op #{op} missing required keys: #{Enum.join(missing, ", ")}",
                path,
                op: op
              )
            ]
          end

        errors ++ walk_nested_exprs(expr, op, path)

      :error ->
        if Map.has_key?(expr, "value") do
          []
        else
          [error(:invalid_core_ir_shape, "unknown expr op #{op}", path, op: op)]
        end
    end
  end

  defp walk_nested_exprs(expr, op, path) do
    nested_keys(op)
    |> Enum.flat_map(fn key ->
      case {key, Map.get(expr, key)} do
        {"branches", list} when op == "case" and is_list(list) ->
          Enum.with_index(list)
          |> Enum.flat_map(fn {branch, idx} ->
            validate_case_branch(branch, path ++ ["branches", idx])
          end)

        {_, nested} when is_map(nested) ->
          validate_expr(nested, path ++ [key])

        {"fields", list} when op in ["record_literal", "record_update"] and is_list(list) ->
          validate_record_fields(list, path ++ ["fields"])

        {"fields", map} when op in ["record_literal", "record_update"] and is_map(map) ->
          validate_record_fields_map(map, path ++ ["fields"])

        {_, list} when is_list(list) ->
          walk_expr_list(list, path ++ [key])

        _ ->
          []
      end
    end)
  end

  defp validate_record_fields(fields, path) when is_list(fields) do
    Enum.with_index(fields)
    |> Enum.flat_map(fn {field, idx} ->
      validate_record_field_entry(field, path ++ [idx])
    end)
  end

  defp validate_record_fields_map(fields, path) when is_map(fields) do
    fields
    |> Enum.flat_map(fn {name, value} ->
      validate_record_field_entry({to_string(name), value}, path ++ [to_string(name)])
    end)
  end

  defp validate_record_field_entry({name, expr}, path)
       when is_binary(name) and is_map(expr) do
    if Map.has_key?(expr, "op") or Map.has_key?(expr, :op) do
      validate_expr(expr, path ++ ["expr"])
    else
      []
    end
  end

  defp validate_record_field_entry(field, path) when is_map(field) do
    field = stringify_keys(field)

    case Map.get(field, "expr") do
      expr when is_map(expr) -> validate_expr(expr, path ++ ["expr"])
      _ -> []
    end
  end

  defp validate_record_field_entry(_, _), do: []

  defp walk_expr_list(list, path) when is_list(list) do
    Enum.with_index(list)
    |> Enum.flat_map(fn {item, idx} ->
      case item do
        map when is_map(map) ->
          validate_expr(map, path ++ [idx])

        list when is_list(list) ->
          walk_expr_list(list, path ++ [idx])

        {_name, expr} when is_map(expr) ->
          validate_expr(expr, path ++ [idx, 1])

        {_name, expr} when is_list(expr) ->
          walk_expr_list(expr, path ++ [idx, 1])

        _ ->
          []
      end
    end)
  end

  defp walk_expr_list(_, _), do: []

  defp validate_case_branch(branch, path) when is_map(branch) do
    branch = stringify_keys(branch)

    []
    |> maybe_add(
      case Map.get(branch, "expr") do
        expr when is_map(expr) -> validate_expr(expr, path ++ ["expr"])
        _ -> []
      end
    )
    |> maybe_add(
      case Map.get(branch, "pattern") do
        pat when is_map(pat) -> validate_pattern(pat, path ++ ["pattern"])
        _ -> []
      end
    )
  end

  defp validate_pattern(pat, path) when is_map(pat) do
    pat = stringify_keys(pat)

    case normalize_op_name(Map.get(pat, "kind")) do
      kind when is_binary(kind) -> []
      _ -> [error(:pattern, ~s(missing or invalid pattern "kind"), path)]
    end
  end

  @spec nested_keys(String.t()) :: [String.t()]
  defp nested_keys(op) do
    base = [
      "expr",
      "value_expr",
      "in_expr",
      "arg",
      "left",
      "right",
      "cond",
      "then_expr",
      "else_expr",
      "subject",
      "body",
      "base"
    ]

    list_keys =
      case op do
        "list_literal" -> ["items", "elements"]
        "tuple" -> ["elements"]
        "call" -> ["args"]
        "qualified_call" -> ["args"]
        "qualified_call1" -> ["args"]
        "constructor_call" -> ["args"]
        "field_call" -> ["args"]
        "lambda" -> []
        _ -> ["args", "items", "elements"]
      end

    (base ++ list_keys) |> Enum.uniq()
  end

  defp require_key(map, key, path) when is_map(map) do
    if Map.has_key?(map, key), do: [], else: [error(:invalid_core_ir_shape, "missing key #{key}", path ++ [key])]
  end

  defp maybe_add(acc, more) when is_list(acc) and is_list(more), do: acc ++ more

  defp error(code, message, path, opts \\ []) do
    %{
      code: to_string(code),
      message: message,
      path: Enum.map(path, &to_string/1)
    }
    |> Map.merge(Map.new(opts))
  end

  defp core_ir_to_map(%CoreIR{} = core_ir) do
    %{
      version: core_ir.version,
      modules: core_ir.modules,
      diagnostics: core_ir.diagnostics,
      deterministic_sha256: core_ir.deterministic_sha256
    }
  end

  defp normalize_wire_map(%CoreIR{} = core_ir), do: core_ir_to_map(core_ir) |> stringify_keys_deep()

  defp normalize_wire_map(map) when is_map(map), do: stringify_keys_deep(map)

  defp stringify_keys_deep(%{__struct__: _} = value) do
    value
    |> Map.from_struct()
    |> stringify_keys_deep()
  end

  defp stringify_keys_deep(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), stringify_keys_deep(v)} end)
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Map.new()
  end

  defp stringify_keys_deep(value) when is_list(value),
    do: Enum.map(value, &stringify_keys_deep/1)

  defp stringify_keys_deep(value), do: value

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  defp normalize_op_name(op) when is_binary(op), do: op
  defp normalize_op_name(op) when is_atom(op), do: to_string(op)
  defp normalize_op_name(_), do: nil
end
