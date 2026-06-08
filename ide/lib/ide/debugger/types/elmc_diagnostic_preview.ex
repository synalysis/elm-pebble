defmodule Ide.Debugger.Types.ElmcDiagnosticPreview do
  @moduledoc """
  Truncated compiler diagnostic rows stored on surface models and `debugger.elmc_*` events.
  """

  alias Ide.Debugger.Types
  @type severity :: String.t()

  @type row :: %{
          optional(:severity) => severity(),
          optional(:message) => String.t(),
          optional(:file) => String.t() | nil,
          optional(:line) => integer() | nil,
          optional(:column) => integer() | nil,
          optional(:source) => String.t() | nil,
          optional(:warning_type) => String.t() | nil,
          optional(:warning_code) => String.t() | nil,
          optional(:warning_constructor) => String.t() | nil,
          optional(:warning_expected_kind) => String.t() | nil,
          optional(:warning_has_arg_pattern) => boolean() | nil,
          optional(String.t()) => Types.wire_input(),
          optional(atom()) => Types.wire_input()
        }

  @type wire_row :: row() | Types.wire_map()

  @type preview :: [row()] | [wire_row()]

  alias Ide.Compiler.Diagnostics

  @spec chunk([Diagnostics.diagnostic_map()], pos_integer()) :: preview()
  def chunk(diagnostics, limit \\ 12) when is_list(diagnostics) do
    diagnostics
    |> Enum.take(limit)
    |> Enum.map(&row_from_diagnostic/1)
  end

  @spec row_from_diagnostic(Diagnostics.diagnostic_map()) :: row()
  def row_from_diagnostic(%{} = d) do
    msg = diagnostic_value(d, :message, "")

    %{
      "severity" => to_string(diagnostic_value(d, :severity, "info")),
      "message" => String.slice(to_string(msg), 0, 240),
      "file" => diagnostic_value(d, :file),
      "line" => diagnostic_value(d, :line),
      "column" => diagnostic_value(d, :column),
      "source" => diagnostic_value(d, :source),
      "warning_type" => diagnostic_value(d, :warning_type),
      "warning_code" => diagnostic_value(d, :warning_code),
      "warning_constructor" => diagnostic_value(d, :warning_constructor),
      "warning_expected_kind" => diagnostic_value(d, :warning_expected_kind),
      "warning_has_arg_pattern" => diagnostic_value(d, :warning_has_arg_pattern)
    }
  end

  @spec diagnostic_value(Diagnostics.diagnostic_map(), atom(), Diagnostics.diagnostic_field()) ::
          Diagnostics.diagnostic_field()
  defp diagnostic_value(%{} = d, key, default \\ nil) when is_atom(key) do
    cond do
      Map.has_key?(d, key) -> Map.get(d, key)
      Map.has_key?(d, Atom.to_string(key)) -> Map.get(d, Atom.to_string(key))
      true -> default
    end
  end
end
