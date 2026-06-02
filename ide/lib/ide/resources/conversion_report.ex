defmodule Ide.Resources.ConversionReport do
  @moduledoc false

  @type warning :: %{code: atom(), element: String.t(), detail: String.t()}
  @type unsupported :: %{tag: String.t(), reason: atom()}
  @type stats :: %{
          commands: non_neg_integer(),
          width: non_neg_integer(),
          height: non_neg_integer()
        }

  @type t :: %__MODULE__{
          warnings: [warning()],
          unsupported: [unsupported()],
          stats: stats() | nil
        }

  defstruct warnings: [], unsupported: [], stats: nil

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec warn(t(), atom(), String.t(), String.t()) :: t()
  def warn(%__MODULE__{} = report, code, element, detail) do
    entry = %{code: code, element: element, detail: detail}
    %{report | warnings: report.warnings ++ [entry]}
  end

  @spec unsupported(t(), String.t(), atom()) :: t()
  def unsupported(%__MODULE__{} = report, tag, reason) do
    entry = %{tag: tag, reason: reason}
    %{report | unsupported: report.unsupported ++ [entry]}
  end

  @spec stats(t(), stats()) :: t()
  def stats(%__MODULE__{} = report, stats) when is_map(stats) do
    %{report | stats: stats}
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = report) do
    %{
      "warnings" =>
        Enum.map(report.warnings, fn w ->
          %{"code" => Atom.to_string(w.code), "element" => w.element, "detail" => w.detail}
        end),
      "unsupported" =>
        Enum.map(report.unsupported, fn u ->
          %{"tag" => u.tag, "reason" => Atom.to_string(u.reason)}
        end),
      "stats" => stats_map(report.stats)
    }
  end

  defp stats_map(nil), do: nil

  defp stats_map(%{commands: commands, width: width, height: height}) do
    %{"commands" => commands, "width" => width, "height" => height}
  end
end
