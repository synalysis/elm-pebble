defmodule Ide.Markdown do
  @moduledoc false

  @mdex_opts [
    plugins: [MDExGFM],
    syntax_highlight: nil
  ]

  @doc """
  Converts Markdown (e.g. package README) to HTML and sanitizes it for safe embedding.
  """
  @spec readme_to_html(String.t()) :: String.t()
  def readme_to_html(markdown) when is_binary(markdown) do
    markdown = String.trim(markdown)

    if markdown == "" do
      ""
    else
      html =
        case MDEx.to_html(markdown, @mdex_opts) do
          {:ok, body} when is_binary(body) and body != "" ->
            body

          _ ->
            fallback_paragraph(markdown)
        end

      HtmlSanitizeEx.html5(html)
    end
  end

  @spec fallback_paragraph(String.t()) :: String.t()
  defp fallback_paragraph(text) do
    "<p>#{Plug.HTML.html_escape(text)}</p>"
  end
end
