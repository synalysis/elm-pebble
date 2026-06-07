defmodule Elmc.Backend.CCodegen.Emit do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Constants
  alias Elmc.Backend.Pebble.Kinds
  alias Elmc.Backend.Pebble.Util

  @spec generated_magic_number_defines() :: String.t()
  def generated_magic_number_defines do
    """
    #{generated_render_op_defines()}
    #define ELMC_CONTEXT_STROKE_WIDTH 1
    #define ELMC_CONTEXT_ANTIALIASED 2
    #define ELMC_CONTEXT_STROKE_COLOR 3
    #define ELMC_CONTEXT_FILL_COLOR 4
    #define ELMC_CONTEXT_TEXT_COLOR 5
    #define ELMC_CONTEXT_COMPOSITING_MODE 6
    #define ELMC_UI_NODE_WINDOW_STACK 1000
    #define ELMC_UI_NODE_WINDOW 1001
    #define ELMC_UI_NODE_CANVAS_LAYER 1002
    #define ELMC_BUTTON_BACK 0
    #define ELMC_BUTTON_UP 1
    #define ELMC_BUTTON_SELECT 2
    #define ELMC_BUTTON_DOWN 3
    #define ELMC_BUTTON_EVENT_PRESSED 1
    #define ELMC_BUTTON_EVENT_RELEASED 2
    #define ELMC_BUTTON_EVENT_LONG_PRESSED 3
    #define ELMC_SUBSCRIPTION_SECOND_CHANGE 1
    #define ELMC_SUBSCRIPTION_BUTTON_UP 2
    #define ELMC_SUBSCRIPTION_BUTTON_SELECT 4
    #define ELMC_SUBSCRIPTION_BUTTON_DOWN 8
    #define ELMC_SUBSCRIPTION_ACCEL_TAP 16
    #define ELMC_SUBSCRIPTION_BATTERY 32
    #define ELMC_SUBSCRIPTION_CONNECTION 64
    #define ELMC_SUBSCRIPTION_APPMESSAGE 4096
    #define ELMC_SUBSCRIPTION_HOUR_CHANGE 1024
    #define ELMC_SUBSCRIPTION_MINUTE_CHANGE 2048
    #define ELMC_SUBSCRIPTION_FRAME_BASE 8192
    #define ELMC_SUBSCRIPTION_BUTTON_RAW 16384
    #define ELMC_SUBSCRIPTION_DAY_CHANGE 65536
    #define ELMC_SUBSCRIPTION_MONTH_CHANGE 131072
    #define ELMC_SUBSCRIPTION_YEAR_CHANGE 262144
    #define ELMC_SUBSCRIPTION_BUTTON_LONG_UP 128
    #define ELMC_SUBSCRIPTION_BUTTON_LONG_SELECT 256
    #define ELMC_SUBSCRIPTION_BUTTON_LONG_DOWN 512
    #define ELMC_SUBSCRIPTION_ACCEL_DATA 32768
    #define ELMC_SUBSCRIPTION_APP_FOCUS 524288
    #define ELMC_SUBSCRIPTION_COMPASS 1048576
    #define ELMC_SUBSCRIPTION_DICTATION 2097152
    #define ELMC_SUBSCRIPTION_UNOBSTRUCTED_AREA 4194304
    #define ELMC_SUBSCRIPTION_HEALTH 2147483648LL
    #define ELMC_TEXT_ALIGN_LEFT 0
    #define ELMC_TEXT_ALIGN_CENTER 1
    #define ELMC_TEXT_ALIGN_RIGHT 2
    #define ELMC_TEXT_OVERFLOW_WORD_WRAP 0
    #define ELMC_TEXT_OVERFLOW_TRAILING_ELLIPSIS 1
    #define ELMC_TEXT_OVERFLOW_FILL 2
    #define ELMC_TEXT_OVERFLOW_SHIFT 2
    #{generated_color_defines()}
    """
  end

  @spec pebble_debug_probe_prelude() :: String.t()
  def pebble_debug_probe_prelude do
    """
    #if defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_GABBRO)
    #include <pebble.h>
    static inline void elmc_agent_generated_probe(uint32_t tag) {
      static uint32_t seen_tags[16];
      static int seen_count = 0;
      for (int i = 0; i < seen_count; i++) {
        if (seen_tags[i] == tag) return;
      }
      if (seen_count >= 16) return;
      DataLoggingSessionRef session = data_logging_create(tag, DATA_LOGGING_BYTE_ARRAY, 1, false);
      if (session) {
        seen_tags[seen_count++] = tag;
        data_logging_finish(session);
      }
    }
    #else
    static inline void elmc_agent_generated_probe(uint32_t tag) {
      (void)tag;
    }
    #endif
    """
  end

  @spec generated_trig_fallback_prelude([String.t()]) :: String.t()
  def generated_trig_fallback_prelude(chunks) do
    source = Enum.join(chunks, "\n")
    needs_sin? = String.contains?(source, "generated_trig_sin_double")
    needs_cos? = String.contains?(source, "generated_trig_cos_double")

    if needs_sin? or needs_cos? do
      cos_helper =
        if needs_cos? do
          """

          static double generated_trig_cos_double(double x) {
            const double half_pi = 1.57079632679489661923;
            return generated_trig_sin_double(x + half_pi);
          }
          """
        else
          ""
        end

      """
      #if !(defined(PBL_PLATFORM_APLITE) || defined(PBL_PLATFORM_BASALT) || defined(PBL_PLATFORM_CHALK) || defined(PBL_PLATFORM_DIORITE) || defined(PBL_PLATFORM_FLINT) || defined(PBL_PLATFORM_EMERY) || defined(PBL_PLATFORM_GABBRO))
      static double generated_trig_normalize_radians(double x) {
        const double pi = 3.14159265358979323846;
        const double two_pi = 6.28318530717958647692;
        while (x > pi) x -= two_pi;
        while (x < -pi) x += two_pi;
        return x;
      }

      static double generated_trig_sin_double(double x) {
        const double pi = 3.14159265358979323846;
        const double half_pi = 1.57079632679489661923;
        x = generated_trig_normalize_radians(x);
        if (x > half_pi) x = pi - x;
        if (x < -half_pi) x = -pi - x;
        double x2 = x * x;
        return x * (1.0
            - x2 / 6.0
            + (x2 * x2) / 120.0
            - (x2 * x2 * x2) / 5040.0
            + (x2 * x2 * x2 * x2) / 362880.0);
      }
      #{cos_helper}
      #endif
      """
    else
      ""
    end
  end

  @spec generated_color_macro(String.t()) :: String.t()
  def generated_color_macro(name) when is_binary(name) do
    name
    |> Macro.underscore()
    |> String.upcase()
    |> then(&"ELMC_COLOR_#{&1}")
  end

  defp generated_color_defines do
    Constants.pebble_color_constants()
    |> Enum.sort_by(fn {name, _value} -> name end)
    |> Enum.map_join("\n", fn {name, value} ->
      "#define #{generated_color_macro(name)} #{value}"
    end)
  end

  defp generated_render_op_defines do
    Kinds.draw_kinds()
    |> Enum.sort_by(fn {_kind, id} -> id end)
    |> Enum.map_join("\n", fn {kind, id} ->
      macro = kind |> Atom.to_string() |> Util.macro_name()
      "#define ELMC_RENDER_OP_#{macro} #{id}"
    end)
  end
end
