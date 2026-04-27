defmodule Ide.Markdown do
  @moduledoc false

  @doc """
  Converts Markdown (e.g. package README) to HTML and sanitizes it for safe embedding.
  """
  @spec readme_to_html(String.t()) :: String.t()
  def readme_to_html(markdown) when is_binary(markdown) do
    markdown = String.trim(markdown)

    if markdown == "" do
      ""
    else
      opts = %Earmark.Options{code_class_prefix: "language-"}

      html =
        case Earmark.as_html(markdown, opts) do
          {:ok, body, _} when is_binary(body) and body != "" ->
            body

          _ ->
            fallback_paragraph(markdown)
        end

      HtmlSanitizeEx.html5(html)
    end
  end

  @spec fallback_paragraph(term()) :: term()
  defp fallback_paragraph(text) do
    "<p>#{Plug.HTML.html_escape(text)}</p>"
  end
end
