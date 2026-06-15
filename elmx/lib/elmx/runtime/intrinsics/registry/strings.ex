defmodule Elmx.Runtime.Intrinsics.Registry.Strings do
  @moduledoc false

  alias Elmx.Runtime.Core.Strings
  alias Elmx.Runtime.Handler

  @type handler :: Handler.t()

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    for {suffix, fun} <- [
          {"all", :all},
          {"any", :any},
          {"cons", :cons},
          {"contains", :contains},
          {"drop_left", :drop_left},
          {"drop_right", :drop_right},
          {"ends_with", :ends_with},
          {"filter", :filter},
          {"foldl", :foldl},
          {"foldr", :foldr},
          {"from_char", :from_char},
          {"from_float", :from_float},
          {"from_int", :from_int},
          {"from_list", :from_list},
          {"indexes", :indexes},
          {"is_empty", :is_empty},
          {"join", :join},
          {"left", :left},
          {"length_val", :length_val},
          {"lines", :lines},
          {"map", :map},
          {"pad", :pad},
          {"pad_left", :pad_left},
          {"pad_right", :pad_right},
          {"repeat", :repeat},
          {"replace", :replace},
          {"reverse", :reverse},
          {"right", :right},
          {"slice", :slice},
          {"split", :split},
          {"starts_with", :starts_with},
          {"to_float", :to_float},
          {"to_int", :to_int},
          {"to_list", :to_list},
          {"to_lower", :to_lower},
          {"to_upper", :to_upper},
          {"trim", :trim},
          {"trim_left", :trim_left},
          {"trim_right", :trim_right},
          {"uncons", :uncons},
          {"words", :words}
        ],
        into: %{} do
      {"elmc_string_#{suffix}", {Strings, fun}}
    end
  end
end
