defmodule ElmEx.Typesys.Diagnostic do
  @moduledoc """
  Structured typesys diagnostics (`source: elm_ex/typesys`).
  """

  @type t :: %{
          required(:source) => String.t(),
          required(:code) => String.t(),
          required(:severity) => String.t(),
          required(:message) => String.t(),
          optional(:module) => String.t() | nil,
          optional(:function) => String.t() | nil,
          optional(:file) => String.t() | nil,
          optional(:line) => integer() | nil,
          optional(:column) => integer() | nil,
          optional(:expected_type) => String.t() | nil,
          optional(:inferred_type) => String.t() | nil,
          optional(:name) => String.t() | nil
        }

  @spec error(String.t(), String.t(), keyword()) :: t()
  def error(code, message, opts \\ []) when is_binary(code) and is_binary(message) do
    build("error", code, message, opts)
  end

  @spec warning(String.t(), String.t(), keyword()) :: t()
  def warning(code, message, opts \\ []) when is_binary(code) and is_binary(message) do
    build("warning", code, message, opts)
  end

  @spec to_bridge(t()) :: map()
  def to_bridge(diag) when is_map(diag) do
    %{
      "type" => "typesys",
      "source" => Map.get(diag, :source, "elm_ex/typesys"),
      "code" => Map.get(diag, :code),
      "severity" => Map.get(diag, :severity, "error"),
      "message" => Map.get(diag, :message),
      "module" => Map.get(diag, :module),
      "function" => Map.get(diag, :function),
      "file" => Map.get(diag, :file),
      "line" => Map.get(diag, :line),
      "column" => Map.get(diag, :column),
      "expected_type" => Map.get(diag, :expected_type),
      "inferred_type" => Map.get(diag, :inferred_type),
      "name" => Map.get(diag, :name)
    }
  end

  defp build(severity, code, message, opts) do
    %{
      source: "elm_ex/typesys",
      code: code,
      severity: severity,
      message: message,
      module: Keyword.get(opts, :module),
      function: Keyword.get(opts, :function),
      file: Keyword.get(opts, :file),
      line: Keyword.get(opts, :line),
      column: Keyword.get(opts, :column),
      expected_type: Keyword.get(opts, :expected_type),
      inferred_type: Keyword.get(opts, :inferred_type),
      name: Keyword.get(opts, :name)
    }
  end
end
