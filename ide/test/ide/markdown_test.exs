defmodule Ide.MarkdownTest do
  use ExUnit.Case, async: true

  alias Ide.Markdown

  test "readme_to_html renders headings and strips script tags" do
    md = "# Title\n\n<script>x</script>\n\n[link](https://example.com)\n"
    html = Markdown.readme_to_html(md)

    assert html =~ "<h1>"
    assert html =~ "Title"
    assert html =~ "example.com"
    refute html =~ "<script>"
  end

  test "readme_to_html returns empty for blank input" do
    assert Markdown.readme_to_html("") == ""
    assert Markdown.readme_to_html("  \n  ") == ""
  end
end
