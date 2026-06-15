defmodule Elmx.Runtime.Intrinsics.Registry.List do
  @moduledoc false

  alias Elmx.Runtime.Core.List, as: CoreList
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    for {suffix, fun} <- [
          {"all", :all},
          {"any", :any},
          {"append", :list_append},
          {"concat", :list_concat},
          {"concat_map", :concat_map},
          {"cons", :list_cons},
          {"drop", :list_drop},
          {"filter", :filter},
          {"filter_map", :filter_map},
          {"foldl", :foldl},
          {"foldr", :foldr},
          {"head", :list_head},
          {"indexed_map", :indexed_map},
          {"intersperse", :list_intersperse},
          {"is_empty", :list_is_empty},
          {"length", :list_length},
          {"map", :map},
          {"map2", :list_map2},
          {"map3", :list_map3},
          {"maximum", :list_maximum},
          {"member", :member},
          {"minimum", :list_minimum},
          {"partition", :list_partition},
          {"product", :list_product},
          {"range", :list_range},
          {"repeat", :list_repeat},
          {"reverse", :list_reverse},
          {"singleton", :list_singleton},
          {"sort", :sort},
          {"sort_by", :sort_by},
          {"sort_with", :sort_with},
          {"sum", :list_sum},
          {"tail", :list_tail},
          {"take", :list_take},
          {"unzip", :list_unzip}
        ],
        into: %{} do
      {"elmc_list_#{suffix}", {CoreList, fun}}
    end
  end
end
