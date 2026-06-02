defmodule Elmx.Runtime.Intrinsics.Registry do
  @moduledoc false

  alias Elmx.Runtime.Cmd
  alias Elmx.Runtime.Core
  alias Elmx.Runtime.Core.Bitwise
  alias Elmx.Runtime.Core.Chars
  alias Elmx.Runtime.Core.Collections
  alias Elmx.Runtime.Core.Debug
  alias Elmx.Runtime.Core.Math
  alias Elmx.Runtime.Core.Process
  alias Elmx.Runtime.Core.Strings
  alias Elmx.Runtime.Core.Task
  alias Elmx.Runtime.Core.Time
  alias Elmx.Runtime.Core.Tuple
  alias Elmx.Runtime.Json.Decode
  alias Elmx.Runtime.Json.Encode

  @type handler :: {module(), atom()} | {module(), atom(), keyword()}

  @spec handlers() :: %{String.t() => handler()}
  def handlers do
    %{}
    |> Map.merge(elmx_core_handlers())
    |> Map.merge(singleton_handlers())
    |> Map.merge(dict_handlers())
    |> Map.merge(set_handlers())
    |> Map.merge(array_handlers())
    |> Map.merge(list_handlers())
    |> Map.merge(string_handlers())
    |> Map.merge(basics_handlers())
    |> Map.merge(bitwise_handlers())
    |> Map.merge(char_handlers())
    |> Map.merge(maybe_result_handlers())
    |> Map.merge(json_decode_handlers())
    |> Map.merge(json_encode_handlers())
    |> Map.merge(tuple_handlers())
    |> Map.merge(platform_handlers())
  end

  defp singleton_handlers do
    %{
      "elmc_append" => {Core, :append},
      "elmc_new_char" => {Core, :new_char}
    }
  end

  defp elmx_core_handlers do
    %{
      "elmx_core_maybe_with_default" => {Core, :maybe_with_default},
      "elmx_core_maybe_map" => {Core, :maybe_map},
      "elmx_core_maybe_and_then" => {Core, :maybe_and_then},
      "elmx_core_maybe_map2" => {Core, :maybe_map2, args: [1, 2, 0]},
      "elmx_core_result_map" => {Core, :result_map},
      "elmx_core_result_with_default" => {Core, :result_with_default},
      "elmx_core_result_and_then" => {Core, :result_and_then},
      "elmx_core_result_map_error" => {Core, :result_map_error},
      "elmx_core_task_map" => {Task, :map},
      "elmx_core_task_map2" => {Task, :map2, args: [0, 1, 2]},
      "elmx_core_task_and_then" => {Task, :and_then},
      "elmx_core_random_generator" => {Core, :random_generator}
    }
  end

  defp dict_handlers, do: prefix_handlers("elmc_dict_", "dict_", Collections)
  defp set_handlers, do: prefix_handlers("elmc_set_", "set_", Collections)
  defp array_handlers, do: prefix_handlers("elmc_array_", "array_", Collections)

  defp list_handlers do
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
      {"elmc_list_#{suffix}", {Core, fun}}
    end
  end

  defp string_handlers do
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

  defp basics_handlers do
    %{
      "elmc_basics_abs" => {Core, :basics_abs},
      "elmc_basics_negate" => {Core, :basics_negate},
      "elmc_basics_not" => {Core, :basics_not},
      "elmc_basics_max" => {Core, :basics_max},
      "elmc_basics_min" => {Core, :basics_min},
      "elmc_basics_mod_by" => {Core, :basics_mod_by},
      "elmc_basics_remainder_by" => {Math, :remainder_by},
      "elmc_basics_clamp" => {Core, :basics_clamp},
      "elmc_basics_compare" => {Core, :basics_compare},
      "elmc_basics_xor" => {Math, :xor},
      "elmc_basics_to_float" => {Math, :to_float},
      "elmc_basics_floor" => {Math, :floor},
      "elmc_basics_ceiling" => {Math, :ceiling},
      "elmc_basics_round" => {Math, :round},
      "elmc_basics_truncate" => {Math, :truncate},
      "elmc_basics_sqrt" => {Math, :sqrt},
      "elmc_basics_sin" => {Math, :sin},
      "elmc_basics_cos" => {Math, :cos},
      "elmc_basics_tan" => {Math, :tan},
      "elmc_basics_asin" => {Math, :asin},
      "elmc_basics_acos" => {Math, :acos},
      "elmc_basics_atan" => {Math, :atan},
      "elmc_basics_atan2" => {Math, :atan2},
      "elmc_basics_degrees" => {Math, :degrees},
      "elmc_basics_radians" => {Math, :radians},
      "elmc_basics_turns" => {Math, :turns},
      "elmc_basics_pow" => {Math, :pow},
      "elmc_basics_log_base" => {Math, :log_base},
      "elmc_basics_is_infinite" => {Math, :is_infinite},
      "elmc_basics_is_nan" => {Math, :is_nan},
      "elmc_basics_to_polar" => {Math, :to_polar},
      "elmc_basics_from_polar" => {Math, :from_polar}
    }
  end

  defp bitwise_handlers do
    %{
      "elmc_bitwise_and" => {Bitwise, :and_},
      "elmc_bitwise_or" => {Bitwise, :or_},
      "elmc_bitwise_xor" => {Bitwise, :xor},
      "elmc_bitwise_complement" => {Bitwise, :complement},
      "elmc_bitwise_shift_left_by" => {Bitwise, :shift_left_by},
      "elmc_bitwise_shift_right_by" => {Bitwise, :shift_right_by},
      "elmc_bitwise_shift_right_zf_by" => {Bitwise, :shift_right_zf_by}
    }
  end

  defp char_handlers do
    %{
      "elmc_char_to_code" => {Chars, :to_code},
      "elmc_char_to_lower" => {Chars, :to_lower},
      "elmc_char_to_upper" => {Chars, :to_upper},
      "elmc_char_is_digit" => {Chars, :is_digit},
      "elmc_char_is_hex_digit" => {Chars, :is_hex_digit},
      "elmc_char_is_oct_digit" => {Chars, :is_oct_digit},
      "elmc_char_is_lower" => {Chars, :is_lower},
      "elmc_char_is_upper" => {Chars, :is_upper},
      "elmc_char_is_alpha" => {Chars, :is_alpha},
      "elmc_char_is_alpha_num" => {Chars, :is_alpha_num}
    }
  end

  defp maybe_result_handlers do
    %{
      "elmc_maybe_with_default" => {Core, :maybe_with_default},
      "elmc_maybe_map" => {Core, :maybe_map},
      "elmc_maybe_map2" => {Core, :maybe_map2, args: [1, 2, 0]},
      "elmc_maybe_and_then" => {Core, :maybe_and_then},
      "elmc_result_map" => {Core, :result_map},
      "elmc_result_map_error" => {Core, :result_map_error},
      "elmc_result_and_then" => {Core, :result_and_then},
      "elmc_result_with_default" => {Core, :result_with_default},
      "elmc_result_to_maybe" => {Core, :result_to_maybe},
      "elmc_result_from_maybe" => {Core, :result_from_maybe}
    }
  end

  defp json_decode_handlers do
    for suffix <- ~w(
         and_then array at bool_decoder dict error_to_string fail field float_decoder
         index int_decoder key_value_pairs lazy list map map2 map3 map4 map5 map6 map7
         maybe null nullable one_of string string_decoder succeed value value_decoder
       ),
       name = json_decode_name(suffix),
       into: %{} do
      {"elmc_json_decode_#{suffix}", {Decode, name}}
    end
  end

  defp json_encode_handlers do
    for {suffix, fun} <- [
          {"array", :list},
          {"set", :list},
          {"bool", :bool},
          {"dict", :dict},
          {"encode", :encode},
          {"float", :float},
          {"int", :int},
          {"list", :list},
          {"null", :null},
          {"object", :object},
          {"string", :string}
        ],
        into: %{} do
      {"elmc_json_encode_#{suffix}", {Encode, fun}}
    end
  end

  defp json_decode_name("string"), do: :decode_string
  defp json_decode_name("value"), do: :decode_value
  defp json_decode_name("bool_decoder"), do: :bool
  defp json_decode_name("int_decoder"), do: :int
  defp json_decode_name("float_decoder"), do: :float
  defp json_decode_name("string_decoder"), do: :string
  defp json_decode_name("value_decoder"), do: :value
  defp json_decode_name(suffix), do: String.to_atom(suffix)

  defp tuple_handlers do
    %{
      "elmc_tuple_first" => {Tuple, :first},
      "elmc_tuple_second" => {Tuple, :second},
      "elmc_tuple_map_first" => {Tuple, :map_first},
      "elmc_tuple_map_second" => {Tuple, :map_second},
      "elmc_tuple_map_both" => {Tuple, :map_both}
    }
  end

  defp platform_handlers do
    %{
      "elmc_debug_log" => {Debug, :log},
      "elmc_debug_todo" => {Debug, :todo},
      "elmc_debug_to_string" => {Debug, :to_string},
      "elmc_task_succeed" => {Task, :succeed},
      "elmc_task_fail" => {Task, :fail},
      "elmc_task_map" => {Task, :map},
      "elmc_task_map2" => {Task, :map2, args: [0, 1, 2]},
      "elmc_task_and_then" => {Task, :and_then},
      "elmc_process_spawn" => {Process, :spawn},
      "elmc_process_sleep" => {Process, :sleep},
      "elmc_process_kill" => {Process, :kill},
      "elmc_time_now_millis" => {Time, :now_millis},
      "elmc_time_zone_offset_minutes" => {Time, :zone_offset_minutes},
      "elmc_cmd_backlight_from_maybe" => {Cmd, :backlight_from_maybe}
    }
  end

  defp prefix_handlers(prefix, fun_prefix, module) do
    for suffix <- suffixes_for_prefix(prefix), into: %{} do
      fun = String.to_atom("#{fun_prefix}#{suffix}")
      {prefix <> suffix, {module, fun}}
    end
  end

  defp suffixes_for_prefix("elmc_dict_"),
    do:
      ~w(diff filter foldl foldr from_list get insert intersect is_empty keys map member merge partition remove singleton size to_list union update values)

  defp suffixes_for_prefix("elmc_set_"),
    do:
      ~w(diff filter foldl foldr from_list insert intersect is_empty map member partition remove singleton size to_list union)

  defp suffixes_for_prefix("elmc_array_"),
    do:
      ~w(append empty filter foldl foldr from_list get indexed_map initialize is_empty length map push repeat set slice to_indexed_list to_list)

  defp suffixes_for_prefix(_), do: []
end
