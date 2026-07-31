defmodule Ide.Formatter do
  @moduledoc """
  Elm source formatting boundary for the IDE.

  The built-in backend uses `ElmEx.Frontend.Pretty` (shared with the layout lexer).
  """
  alias Ide.Formatter.EditEngine
  alias Ide.Formatter.EditPatch
  alias Ide.Formatter.Types
  alias ElmEx.Frontend.Pretty

  @type diagnostic :: Types.diagnostic()
  @type format_result :: Types.format_result()

  @type edit_patch_result :: %{
          replace_from: non_neg_integer(),
          replace_to: non_neg_integer(),
          inserted_text: String.t(),
          cursor_start: non_neg_integer(),
          cursor_end: non_neg_integer()
        }

  @default_engine :pretty

  @spec format(String.t(), keyword()) :: {:ok, format_result()} | {:error, Types.parse_error()}
  def format(source, opts \\ []) when is_binary(source) do
    case Keyword.get(opts, :engine, default_engine()) do
      :pretty -> format_with_pretty(source, opts)
      other -> {:error, unsupported_engine_error(other)}
    end
  end

  @spec format_with_pretty(String.t(), Types.format_opts()) ::
          {:ok, format_result()} | {:error, Types.parse_error()}
  defp format_with_pretty(source, opts) do
    path = Keyword.get(opts, :path, "Main.elm")

    case Pretty.format_module_source_preserve(path, source, pretty_opts(opts)) do
      {:ok, formatted} ->
        {:ok,
         %{
           formatted_source: formatted,
           changed?: formatted != source,
           diagnostics: [],
           formatter: "pretty-v1",
           details: %{
             pipeline: "pretty-v1",
             backend: :pretty
           }
         }}

      {:error, reason} ->
        {:error, parse_error_from_reason(reason)}
    end
  end

  @spec compute_tab_edit(String.t(), non_neg_integer(), non_neg_integer(), boolean()) ::
          edit_patch_result()
  def compute_tab_edit(content, start_offset, end_offset, outdent?)
      when is_binary(content) and is_integer(start_offset) and is_integer(end_offset) do
    result = EditEngine.compute_tab_edit(content, start_offset, end_offset, outdent?)

    EditPatch.from_contents(
      content,
      result.next_content,
      result.cursor_start,
      result.cursor_end
    )
  end

  @spec compute_enter_edit(String.t(), non_neg_integer(), non_neg_integer()) ::
          edit_patch_result()
  def compute_enter_edit(content, start_offset, end_offset)
      when is_binary(content) and is_integer(start_offset) and is_integer(end_offset) do
    result = EditEngine.compute_enter_edit(content, start_offset, end_offset)

    EditPatch.from_contents(
      content,
      result.next_content,
      result.cursor_start,
      result.cursor_end
    )
  end

  @spec default_engine() :: :pretty | :ide
  defp default_engine do
    Application.get_env(:ide, Ide.Formatter, [])
    |> Keyword.get(:engine, @default_engine)
  end

  @spec pretty_opts(Types.format_opts()) :: Pretty.opts()
  defp pretty_opts(opts) do
    opts
    |> Keyword.take([:width, :indent])
  end

  @spec parse_error_from_reason(term()) :: Types.parse_error()
  defp parse_error_from_reason(reason) do
    %{
      severity: "error",
      source: "formatter/parser",
      message: "Cannot format: #{inspect(reason)}",
      line: nil,
      column: nil
    }
  end

  @spec unsupported_engine_error(term()) :: Types.parse_error()
  defp unsupported_engine_error(engine) do
    %{
      severity: "error",
      source: "formatter/engine",
      message: "Unsupported formatter engine: #{inspect(engine)}",
      line: nil,
      column: nil
    }
  end
end
