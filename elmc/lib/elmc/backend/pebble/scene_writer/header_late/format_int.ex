defmodule Elmc.Backend.Pebble.SceneWriter.HeaderLate.FormatInt do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if ELMC_PEBBLE_FEATURE_DRAW_TEXT || ELMC_PEBBLE_FEATURE_DRAW_TEXT_LABEL
    static inline int elmc_scene_format_nonzero_int_at(char *text, int start, elmc_int_t value) {
      elmc_int_t direct_value = value;
      char direct_digits[12];
      int direct_digit_count = 0;
      int direct_text_i = start;
      int direct_negative = direct_value < 0;
      if (direct_negative && direct_text_i < 63) {
        text[direct_text_i++] = '-';
      }
      do {
        elmc_int_t direct_digit = direct_value % 10;
        if (direct_digit < 0) direct_digit = -direct_digit;
        direct_digits[direct_digit_count++] = (char)('0' + direct_digit);
        direct_value /= 10;
      } while (direct_value != 0 && direct_digit_count < (int)sizeof(direct_digits));
      while (direct_digit_count > 0 && direct_text_i < 63) {
        text[direct_text_i++] = direct_digits[--direct_digit_count];
      }
      text[direct_text_i] = '\\0';
      return direct_text_i;
    }

    static inline void elmc_scene_text_from_nonzero_int(char *text, elmc_int_t value) {
      (void)elmc_scene_format_nonzero_int_at(text, 0, value);
    }

    static inline void elmc_scene_text_prefix_and_nonzero_int(char *text, const char *prefix, elmc_int_t value) {
      int direct_text_i = 0;
      while (prefix && prefix[direct_text_i] && direct_text_i < 63) {
        text[direct_text_i] = prefix[direct_text_i];
        direct_text_i++;
      }
      (void)elmc_scene_format_nonzero_int_at(text, direct_text_i, value);
    }
    #endif

    """
  end
end
