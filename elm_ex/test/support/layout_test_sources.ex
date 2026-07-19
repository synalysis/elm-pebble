defmodule ElmEx.Test.LayoutTestSources do
  @moduledoc false

  alias ElmEx.Frontend.Layout

  @spec extract_heredocs(String.t()) :: [String.t()]
  def extract_heredocs(path) when is_binary(path) do
    path
    |> File.read!()
    |> extract_heredocs_from_content()
  end

  @spec extract_heredocs_from_content(String.t()) :: [String.t()]
  def extract_heredocs_from_content(content) when is_binary(content) do
    content
    |> String.split(~s/"""/)
    |> Enum.drop(1)
    |> Enum.take_every(2)
    |> Enum.map(&normalize_extracted_heredoc/1)
    |> Enum.reject(&(&1 == ""))
  end

  @spec normalize_extracted_heredoc(String.t()) :: String.t()
  def normalize_extracted_heredoc(source) when is_binary(source) do
    if String.contains?(source, "\n") do
      source
      |> String.trim_trailing()
      |> String.replace(~r/^\s*\n/u, "")
      |> Layout.dedent_uniform_leading_whitespace()
    else
      String.trim(source)
    end
  end
end
