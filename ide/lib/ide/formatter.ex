defmodule Ide.Formatter do
  @moduledoc """
  Parser-backed formatting boundary for Elm sources.

  This starts with a conservative normalization pass and parser validation.
  """
  alias Ide.Formatter.EditEngine
  alias Ide.Formatter.EditPatch
  alias Ide.Formatter.Printer.Pipeline
  alias Ide.Formatter.Semantics.Finalize
  alias Ide.Formatter.Semantics.Layout
  alias Ide.Formatter.Semantics.Normalize
  alias Ide.Formatter.Semantics.Parse
  alias Ide.Formatter.Types

  @type diagnostic :: Types.diagnostic()

  @type format_result :: Types.format_result()

  @type edit_patch_result :: %{
          replace_from: non_neg_integer(),
          replace_to: non_neg_integer(),
          inserted_text: String.t(),
          cursor_start: non_neg_integer(),
          cursor_end: non_neg_integer()
        }

  @spec format(String.t(), keyword()) :: {:ok, format_result()} | {:error, map()}
  def format(source, opts \\ []) when is_binary(source) do
    if semantics_pipeline_enabled?(opts) do
      format_with_semantics_pipeline(source, opts)
    else
      format_with_legacy_pipeline(source, opts)
    end
  end

  @spec format_with_semantics_pipeline(String.t(), Types.format_opts()) ::
          {:ok, format_result()} | {:error, map()}
  defp format_with_semantics_pipeline(source, opts) do
    with {:ok, parser_payload} <- parse_stage(source, opts),
         {:ok, laid_out} <- layout_stage(source),
         {:ok, normalized} <- normalize_stage(laid_out, parser_payload, opts),
         {:ok, finalized} <- finalize_stage(normalized) do
      {:ok,
       %{
         formatted_source: finalized,
         changed?: finalized != source,
         diagnostics: parser_payload.diagnostics,
         formatter: "semantics-v1",
         details: %{
           parser_payload_reused?: parser_payload[:reused?] == true,
           pipeline: "semantics-v1"
         }
       }}
    end
  end

  @spec format_with_legacy_pipeline(String.t(), Types.format_opts()) ::
          {:ok, format_result()} | {:error, map()}
  defp format_with_legacy_pipeline(source, opts) do
    with {:ok, parser_payload} <- parse_stage(source, opts),
         {:ok, laid_out} <- layout_stage(source),
         {:ok, normalized} <- normalize_stage(laid_out, parser_payload, opts),
         {:ok, finalized} <- finalize_stage(normalized) do
      diagnostics = add_fallback_diagnostic_tag(parser_payload.diagnostics)

      {:ok,
       %{
         formatted_source: finalized,
         changed?: finalized != source,
         diagnostics: diagnostics,
         formatter: "legacy-v1",
         details: %{
           parser_payload_reused?: parser_payload[:reused?] == true,
           pipeline: "legacy-v1"
         }
       }}
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

  @spec parse_stage(String.t(), Types.format_opts()) ::
          {:ok, Types.parse_payload()} | {:error, Types.parse_error()}
  defp parse_stage(source, opts), do: Parse.validate_with_parser(source, opts)

  @spec layout_stage(String.t()) :: {:ok, String.t()} | {:error, map()}
  defp layout_stage(source), do: {:ok, Layout.normalize_layout(source)}

  @spec normalize_stage(String.t(), Types.parse_payload(), Types.format_opts()) ::
          {:ok, String.t()} | {:error, map()}
  defp normalize_stage(source, parser_payload, opts) when is_map(parser_payload) do
    metadata = parser_payload.metadata

    if parser_payload[:fallback?] == true do
      {:ok, Normalize.apply(source, metadata, opts)}
    else
      {:ok, Pipeline.apply(source, metadata, opts)}
    end
  end

  @spec finalize_stage(String.t()) :: {:ok, String.t()} | {:error, map()}
  defp finalize_stage(source), do: {:ok, Finalize.finalize(source)}

  @spec semantics_pipeline_enabled?(Types.format_opts()) :: boolean()
  defp semantics_pipeline_enabled?(opts) do
    default =
      Application.get_env(:ide, Ide.Formatter, [])
      |> Keyword.get(:semantics_pipeline, true)

    Keyword.get(opts, :semantics_pipeline, default)
  end

  @spec add_fallback_diagnostic_tag([diagnostic()]) :: [diagnostic()]
  defp add_fallback_diagnostic_tag(diagnostics) when is_list(diagnostics) do
    [
      %{
        severity: "info",
        source: "formatter/pipeline",
        message: "Using legacy formatter pipeline fallback.",
        line: nil,
        column: nil
      }
      | diagnostics
    ]
  end
end
