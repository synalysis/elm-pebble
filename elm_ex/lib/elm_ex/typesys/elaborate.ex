defmodule ElmEx.Typesys.Elaborate do
  @moduledoc """
  Copy `:elm_type` / `:elm_exhaustive?` across lowerer rewrites.
  """

  @spec merge_meta(map() | nil, map() | nil) :: map() | nil
  def merge_meta(rewritten, original) when is_map(rewritten) and is_map(original) do
    rewritten
    |> copy(original, :elm_type)
    |> copy(original, :elm_exhaustive?)
  end

  def merge_meta(rewritten, _original), do: rewritten

  defp copy(dest, src, key) do
    case {Map.get(dest, key), Map.get(src, key)} do
      {nil, value} when not is_nil(value) -> Map.put(dest, key, value)
      _ -> dest
    end
  end
end
