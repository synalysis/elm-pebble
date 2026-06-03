defmodule Elmx.Runtime.Intrinsics.Registry.Prefix do
  @moduledoc false

  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers(String.t(), String.t(), module()) :: %{String.t() => handler()}
  def handlers(prefix, fun_prefix, module) do
    for suffix <- suffixes_for_prefix(prefix), into: %{} do
      fun = String.to_atom("#{fun_prefix}#{suffix}")
      {prefix <> suffix, {module, fun}}
    end
  end

  @spec suffixes_for_prefix(String.t()) :: [String.t()]
  def suffixes_for_prefix("elmc_dict_"),
    do:
      ~w(diff filter foldl foldr from_list get insert intersect is_empty keys map member merge partition remove singleton size to_list union update values)

  def suffixes_for_prefix("elmc_set_"),
    do:
      ~w(diff filter foldl foldr from_list insert intersect is_empty map member partition remove singleton size to_list union)

  def suffixes_for_prefix("elmc_array_"),
    do:
      ~w(append empty filter foldl foldr from_list get indexed_map initialize is_empty length map push repeat set slice to_indexed_list to_list)

  def suffixes_for_prefix(_), do: []
end
