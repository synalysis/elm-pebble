defmodule ElmEx.DiagnosticFormatter do
  @moduledoc """
  Produces human-readable compiler diagnostics inspired by Elm's style.
  """

  @spec format_error(map()) :: String.t()
  def format_error(%{kind: :config_error, reason: :missing_elm_json, path: path}) do
    [
      "-- MISSING elm.json -------------------------------------------------------- elm_ex\n\n",
      "I cannot find an elm.json file for this project.\n\n",
      "Expected at:\n",
      "    ",
      path,
      "\n\n",
      "Try running `elm init` in your project root first.\n"
    ]
    |> IO.iodata_to_binary()
  end

  def format_error(%{kind: :config_error, reason: reason}) do
    "-- PROJECT CONFIG ERROR ---------------------------------------------------- elm_ex\n\n" <>
      "I hit a project configuration problem:\n\n" <>
      "    " <> inspect(reason) <> "\n"
  end

  def format_error(%{kind: :parse_error, path: path} = error) do
    line = Map.get(error, :line, "?")
    reason = Map.get(error, :reason, :unknown)

    "-- PARSE ERROR ------------------------------------------------------------- elm_ex\n\n" <>
      "I got stuck while parsing this module:\n\n" <>
      "    " <>
      path <>
      ":" <>
      to_string(line) <>
      "\n\n" <>
      "Details:\n" <>
      "    " <>
      format_parse_reason(reason) <>
      "\n\n" <>
      "Hint: check module/import headers and punctuation near that line.\n"
  end

  def format_error(%{kind: :elm_check_failed, diagnostics: diagnostics, raw: raw}) do
    rendered =
      diagnostics
      |> Enum.map(&format_elm_report/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    if rendered == "" do
      "-- ELM CHECK FAILED ------------------------------------------------------- elm_ex\n\n" <>
        "elm make reported a failure, but I could not decode a structured report.\n\n" <>
        raw
    else
      rendered
    end
  end

  def format_error(error) do
    "-- COMPILER ERROR ---------------------------------------------------------- elm_ex\n\n" <>
      inspect(error, pretty: true) <> "\n"
  end

  @spec format_warnings([map()]) :: String.t()
  def format_warnings(warnings) when is_list(warnings) do
    warnings
    |> Enum.map(&format_warning/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  @spec format_warning(map()) :: String.t()
  defp format_warning(%{"type" => "lowerer-warning"} = warning) do
    source = Map.get(warning, "source", "lowerer")
    module_name = Map.get(warning, "module", "<unknown>")
    function_name = Map.get(warning, "function", "<unknown>")
    line = Map.get(warning, "line")
    message = Map.get(warning, "message", inspect(warning))
    location = format_warning_location(module_name, function_name, line)
    details = format_structured_warning_details(warning)

    "-- LOWERER WARNING --------------------------------------------------------- elm_ex\n\n" <>
      "Source:\n" <>
      "    #{source}\n\n" <>
      "Location:\n" <>
      "    #{location}\n\n" <>
      details <>
      "Details:\n" <>
      "    #{message}\n"
  end

  defp format_warning(%{source: "lowerer/pattern"} = warning) do
    module_name = Map.get(warning, :module, "<unknown>")
    function_name = Map.get(warning, :function, "<unknown>")
    line = Map.get(warning, :line)
    message = Map.get(warning, :message, inspect(warning))
    location = format_warning_location(module_name, function_name, line)
    details = format_structured_warning_details(warning)

    "-- LOWERER WARNING --------------------------------------------------------- elm_ex\n\n" <>
      "Source:\n" <>
      "    lowerer/pattern\n\n" <>
      "Location:\n" <>
      "    #{location}\n\n" <>
      details <>
      "Details:\n" <>
      "    #{message}\n"
  end

  defp format_warning(_), do: ""

  @spec format_warning_location(String.t() | nil, String.t() | nil, integer() | nil) :: String.t()
  defp format_warning_location(module_name, function_name, line)
       when is_integer(line) and line > 0 do
    "#{module_name}.#{function_name}:#{line}"
  end

  defp format_warning_location(module_name, function_name, _line) do
    "#{module_name}.#{function_name}"
  end

  @spec format_structured_warning_details(map()) :: String.t()
  defp format_structured_warning_details(warning) when is_map(warning) do
    code = Map.get(warning, "code", Map.get(warning, :code))
    constructor = Map.get(warning, "constructor", Map.get(warning, :constructor))
    expected_kind = Map.get(warning, "expected_kind", Map.get(warning, :expected_kind))
    has_arg_pattern = Map.get(warning, "has_arg_pattern", Map.get(warning, :has_arg_pattern))

    fields =
      []
      |> maybe_detail_line("Code", code)
      |> maybe_detail_line("Constructor", constructor)
      |> maybe_detail_line("Expected Kind", expected_kind)
      |> maybe_detail_line("Has Arg Pattern", has_arg_pattern)

    if fields == [] do
      ""
    else
      "Structured:\n" <> Enum.join(fields, "") <> "\n"
    end
  end

  @spec maybe_detail_line([String.t()], String.t(), term()) :: [String.t()]
  defp maybe_detail_line(lines, _label, nil), do: lines

  defp maybe_detail_line(lines, label, value) do
    rendered =
      case value do
        atom when is_atom(atom) -> Atom.to_string(atom)
        other -> to_string(other)
      end

    lines ++ ["    #{label}: #{rendered}\n"]
  end

  @spec format_parse_reason(atom() | term()) :: String.t()
  defp format_parse_reason({:illegal, charlist}) when is_list(charlist) do
    "illegal token: #{List.to_string(charlist)}"
  end

  defp format_parse_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_parse_reason(reason), do: inspect(reason)

  @spec format_elm_report(map() | list() | term()) :: String.t()
  defp format_elm_report(%{"type" => "compile-errors", "errors" => errors})
       when is_list(errors) do
    errors
    |> Enum.flat_map(fn per_file ->
      path = Map.get(per_file, "path", "<unknown>")

      Map.get(per_file, "problems", [])
      |> Enum.map(fn problem -> format_problem(path, problem) end)
    end)
    |> Enum.join("\n\n")
  end

  defp format_elm_report(%{"type" => "error", "title" => title, "message" => message}) do
    "-- #{title} --------------------------------------------------------------- elm_ex\n\n" <>
      flatten_message(message)
  end

  defp format_elm_report(_), do: ""

  @spec format_problem(String.t(), map()) :: String.t()
  defp format_problem(path, problem) do
    title = Map.get(problem, "title", "ELM ERROR")
    region = Map.get(problem, "region", %{})
    line = get_in(region, ["start", "line"]) || "?"
    column = get_in(region, ["start", "column"]) || "?"
    message = flatten_message(Map.get(problem, "message", []))

    "-- #{title} " <>
      String.duplicate("-", max(1, 74 - String.length(title))) <>
      " elm_ex\n\n" <>
      path <>
      ":" <>
      to_string(line) <>
      ":" <>
      to_string(column) <>
      "\n\n" <>
      message
  end

  @spec flatten_message(term()) :: String.t()
  defp flatten_message(parts) when is_list(parts) do
    parts
    |> Enum.map(&flatten_message/1)
    |> Enum.join("")
    |> String.replace("\n\n\n", "\n\n")
    |> String.trim()
  end

  defp flatten_message(%{"string" => value}) when is_binary(value), do: value
  defp flatten_message(%{"text" => value}) when is_binary(value), do: value
  defp flatten_message(%{"href" => value}) when is_binary(value), do: value
  defp flatten_message(%{"bold" => value}) when is_boolean(value), do: ""
  defp flatten_message(value) when is_binary(value), do: value
  defp flatten_message(_), do: ""
end
