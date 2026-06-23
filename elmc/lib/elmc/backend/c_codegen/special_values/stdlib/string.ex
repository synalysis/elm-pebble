defmodule Elmc.Backend.CCodegen.SpecialValues.Stdlib.String do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Types

  @behaviour Elmc.Backend.CCodegen.SpecialValues.Handler

  @impl true
  @spec special_value_from_target(String.t(), Types.special_value_args()) ::
          Types.special_value_result()
  def special_value_from_target("Char.toCode", [value]),
    do: %{op: :runtime_call, function: "elmc_char_to_code", args: [value]}

  def special_value_from_target("String.append", [left, right]),
    do: %{op: :runtime_call, function: "elmc_append", args: [left, right]}

  def special_value_from_target("String.isEmpty", [value]),
    do: %{op: :runtime_call, function: "elmc_string_is_empty", args: [value]}

  def special_value_from_target("String.fromInt", []),
    do: %{
      op: :lambda,
      args: ["__n"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_from_int",
        args: [%{op: :var, name: "__n"}]
      }
    }

  def special_value_from_target("String.fromFloat", []),
    do: %{
      op: :lambda,
      args: ["__f"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_from_float",
        args: [%{op: :var, name: "__f"}]
      }
    }

  def special_value_from_target("String.toInt", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_to_int", args: [%{op: :var, name: "__s"}]}
    }

  def special_value_from_target("String.toFloat", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_to_float",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.isEmpty", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_is_empty",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.length", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_length_val",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.reverse", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_reverse",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.toUpper", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_to_upper",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.toLower", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{
        op: :runtime_call,
        function: "elmc_string_to_lower",
        args: [%{op: :var, name: "__s"}]
      }
    }

  def special_value_from_target("String.trim", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_trim", args: [%{op: :var, name: "__s"}]}
    }

  def special_value_from_target("String.words", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_words", args: [%{op: :var, name: "__s"}]}
    }

  def special_value_from_target("String.lines", []),
    do: %{
      op: :lambda,
      args: ["__s"],
      body: %{op: :runtime_call, function: "elmc_string_lines", args: [%{op: :var, name: "__s"}]}
    }

  def special_value_from_target("Char.toCode", []),
    do: %{
      op: :lambda,
      args: ["__ch"],
      body: %{op: :runtime_call, function: "elmc_char_to_code", args: [%{op: :var, name: "__ch"}]}
    }

  def special_value_from_target("Char.fromCode", []),
    do: %{
      op: :lambda,
      args: ["__c"],
      body: %{op: :runtime_call, function: "elmc_new_char", args: [%{op: :var, name: "__c"}]}
    }

  def special_value_from_target("String.length", [s]),
    do: %{op: :runtime_call, function: "elmc_string_length_val", args: [s]}

  def special_value_from_target("String.reverse", [s]),
    do: %{op: :runtime_call, function: "elmc_string_reverse", args: [s]}

  def special_value_from_target("String.repeat", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_repeat", args: [n, s]}

  def special_value_from_target("String.replace", [old, new_s, s]),
    do: %{op: :runtime_call, function: "elmc_string_replace", args: [old, new_s, s]}

  def special_value_from_target("String.fromInt", [n]),
    do: %{op: :runtime_call, function: "elmc_string_from_int", args: [n]}

  def special_value_from_target("String.toInt", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_int", args: [s]}

  def special_value_from_target("String.fromFloat", [f]),
    do: %{op: :runtime_call, function: "elmc_string_from_float", args: [f]}

  def special_value_from_target("String.toFloat", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_float", args: [s]}

  def special_value_from_target("String.toUpper", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_upper", args: [s]}

  def special_value_from_target("String.toLower", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_lower", args: [s]}

  def special_value_from_target("String.trim", [s]),
    do: %{op: :runtime_call, function: "elmc_string_trim", args: [s]}

  def special_value_from_target("String.trimLeft", [s]),
    do: %{op: :runtime_call, function: "elmc_string_trim_left", args: [s]}

  def special_value_from_target("String.trimRight", [s]),
    do: %{op: :runtime_call, function: "elmc_string_trim_right", args: [s]}

  def special_value_from_target("String.contains", [sub, s]),
    do: %{op: :runtime_call, function: "elmc_string_contains", args: [sub, s]}

  def special_value_from_target("String.startsWith", [prefix, s]),
    do: %{op: :runtime_call, function: "elmc_string_starts_with", args: [prefix, s]}

  def special_value_from_target("String.endsWith", [suffix, s]),
    do: %{op: :runtime_call, function: "elmc_string_ends_with", args: [suffix, s]}

  def special_value_from_target("String.split", [sep, s]),
    do: %{op: :runtime_call, function: "elmc_string_split", args: [sep, s]}

  def special_value_from_target("String.join", [sep, list]),
    do: %{op: :runtime_call, function: "elmc_string_join", args: [sep, list]}

  def special_value_from_target("String.words", [s]),
    do: %{op: :runtime_call, function: "elmc_string_words", args: [s]}

  def special_value_from_target("String.lines", [s]),
    do: %{op: :runtime_call, function: "elmc_string_lines", args: [s]}

  def special_value_from_target("String.slice", [start, end_idx, s]),
    do: %{op: :runtime_call, function: "elmc_string_slice", args: [start, end_idx, s]}

  def special_value_from_target("String.left", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_left", args: [n, s]}

  def special_value_from_target("String.right", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_right", args: [n, s]}

  def special_value_from_target("String.dropLeft", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_drop_left", args: [n, s]}

  def special_value_from_target("String.dropRight", [n, s]),
    do: %{op: :runtime_call, function: "elmc_string_drop_right", args: [n, s]}

  def special_value_from_target("String.cons", [ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_cons", args: [ch, s]}

  def special_value_from_target("String.uncons", [s]),
    do: %{op: :runtime_call, function: "elmc_string_uncons", args: [s]}

  def special_value_from_target("String.toList", [s]),
    do: %{op: :runtime_call, function: "elmc_string_to_list", args: [s]}

  def special_value_from_target("String.fromList", [list]),
    do: %{op: :runtime_call, function: "elmc_string_from_list", args: [list]}

  def special_value_from_target("String.fromChar", [ch]),
    do: %{op: :runtime_call, function: "elmc_string_from_char", args: [ch]}

  def special_value_from_target("String.pad", [n, ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_pad", args: [n, ch, s]}

  def special_value_from_target("String.padLeft", [n, ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_pad_left", args: [n, ch, s]}

  def special_value_from_target("String.padRight", [n, ch, s]),
    do: %{op: :runtime_call, function: "elmc_string_pad_right", args: [n, ch, s]}

  def special_value_from_target("String.map", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_map", args: [f, s]}

  def special_value_from_target("String.filter", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_filter", args: [f, s]}

  def special_value_from_target("String.foldl", [f, acc, s]),
    do: %{op: :runtime_call, function: "elmc_string_foldl", args: [f, acc, s]}

  def special_value_from_target("String.foldr", [f, acc, s]),
    do: %{op: :runtime_call, function: "elmc_string_foldr", args: [f, acc, s]}

  def special_value_from_target("String.any", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_any", args: [f, s]}

  def special_value_from_target("String.all", [f, s]),
    do: %{op: :runtime_call, function: "elmc_string_all", args: [f, s]}

  def special_value_from_target("String.indexes", [sub, s]),
    do: %{op: :runtime_call, function: "elmc_string_indexes", args: [sub, s]}

  def special_value_from_target("String.indices", [sub, s]),
    do: %{op: :runtime_call, function: "elmc_string_indexes", args: [sub, s]}

  # --- elm/core: Tuple ---
  def special_value_from_target("Char.fromCode", [code]),
    do: %{op: :runtime_call, function: "elmc_char_from_code", args: [code]}

  def special_value_from_target("Char.isUpper", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_upper", args: [ch]}

  def special_value_from_target("Char.isLower", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_lower", args: [ch]}

  def special_value_from_target("Char.isAlpha", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_alpha", args: [ch]}

  def special_value_from_target("Char.isAlphaNum", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_alpha_num", args: [ch]}

  def special_value_from_target("Char.isDigit", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_digit", args: [ch]}

  def special_value_from_target("Char.isOctDigit", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_oct_digit", args: [ch]}

  def special_value_from_target("Char.isHexDigit", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_is_hex_digit", args: [ch]}

  def special_value_from_target("Char.toUpper", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_upper", args: [ch]}

  def special_value_from_target("Char.toLower", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_lower", args: [ch]}

  def special_value_from_target("Char.toLocaleUpper", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_upper", args: [ch]}

  def special_value_from_target("Char.toLocaleLower", [ch]),
    do: %{op: :runtime_call, function: "elmc_char_to_lower", args: [ch]}

  # --- elm/core: Dict (extended) ---

  def special_value_from_target(_target, _args), do: nil
end
