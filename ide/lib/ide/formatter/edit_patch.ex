defmodule Ide.Formatter.EditPatch do
  @moduledoc false

  @type t :: %{
          replace_from: non_neg_integer(),
          replace_to: non_neg_integer(),
          inserted_text: String.t(),
          cursor_start: non_neg_integer(),
          cursor_end: non_neg_integer()
        }

  @spec from_contents(String.t(), String.t(), non_neg_integer(), non_neg_integer()) :: t()
  def from_contents(before, updated_content, cursor_start, cursor_end)
      when is_binary(before) and is_binary(updated_content) do
    prefix_len = common_prefix_len(before, updated_content)
    suffix_len = common_suffix_len(before, updated_content, prefix_len)

    replace_from = prefix_len
    replace_to = String.length(before) - suffix_len
    inserted_to = String.length(updated_content) - suffix_len
    inserted_text = String.slice(updated_content, replace_from, inserted_to - replace_from)

    %{
      replace_from: replace_from,
      replace_to: replace_to,
      inserted_text: inserted_text,
      cursor_start: clamp(cursor_start, String.length(updated_content)),
      cursor_end: clamp(cursor_end, String.length(updated_content))
    }
  end

  @spec common_prefix_len(term(), term()) :: term()
  defp common_prefix_len(a, b),
    do: common_prefix_len(a, b, 0, min(String.length(a), String.length(b)))

  defp common_prefix_len(_a, _b, idx, max_len) when idx >= max_len, do: idx

  defp common_prefix_len(a, b, idx, max_len) do
    if String.at(a, idx) == String.at(b, idx) do
      common_prefix_len(a, b, idx + 1, max_len)
    else
      idx
    end
  end

  @spec common_suffix_len(term(), term(), term()) :: term()
  defp common_suffix_len(a, b, prefix_len) do
    max_suffix = min(String.length(a), String.length(b)) - prefix_len
    common_suffix_len(a, b, 0, max_suffix)
  end

  defp common_suffix_len(_a, _b, suffix, max_suffix) when suffix >= max_suffix, do: suffix

  defp common_suffix_len(a, b, suffix, max_suffix) do
    a_idx = String.length(a) - 1 - suffix
    b_idx = String.length(b) - 1 - suffix

    if String.at(a, a_idx) == String.at(b, b_idx) do
      common_suffix_len(a, b, suffix + 1, max_suffix)
    else
      suffix
    end
  end

  @spec clamp(term(), term()) :: term()
  defp clamp(value, max_len) when is_integer(value) do
    value |> max(0) |> min(max_len)
  end
end
