defmodule Elmc.Backend.CCodegen.Emit do
  @moduledoc false

  alias Elmc.Backend.CCodegen.Constants
  alias Elmc.Backend.CCodegen.ProdMode
  alias Elmc.Backend.CCodegen.Types
  alias Elmc.Backend.Pebble.Kinds
  alias Elmc.Backend.Pebble.Util

  @spec generated_magic_number_defines() :: String.t()
  def generated_magic_number_defines do
    all_magic_number_defines()
  end

  @spec generated_magic_number_defines([String.t()], keyword() | map()) :: String.t()
  def generated_magic_number_defines(chunks, opts) do
    if opts[:strip_dead_code] == false do
      all_magic_number_defines()
    else
      source = Enum.join(chunks, "\n")
      used_tokens = used_macro_tokens(source)

      [
        generated_render_op_defines(used_tokens),
        used_fixed_magic_number_defines(used_tokens),
        generated_color_defines(used_tokens)
      ]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    end
  end

  defp all_magic_number_defines do
    """
    #{generated_render_op_defines()}
    #{fixed_magic_number_defines()}
    #{generated_color_defines()}
    """
  end

  @spec pebble_debug_probe_prelude(Types.codegen_opts() | nil) :: String.t()
  def pebble_debug_probe_prelude(opts \\ nil) do
    if prod_mode?(opts), do: "", else: pebble_debug_probe_prelude_impl()
  end

  defp prod_mode?(nil), do: ProdMode.enabled?()

  defp prod_mode?(opts) when is_map(opts), do: Map.get(opts, :prod, false) == true

  defp prod_mode?(_), do: ProdMode.enabled?()

  defp pebble_debug_probe_prelude_impl do
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

  @spec generated_render_cmd_prelude([String.t()]) :: String.t()
  def generated_render_cmd_prelude(chunks) do
    source = Enum.join(chunks, "\n")

    if String.contains?(source, "elmc_render_cmd6") do
      """
      static inline ElmcValue *elmc_render_cmd6(
          elmc_int_t kind, elmc_int_t p0, elmc_int_t p1, elmc_int_t p2,
          elmc_int_t p3, elmc_int_t p4, elmc_int_t p5) {
        ElmcValue *out = NULL;
        return elmc_render_cmd6_take(&out, kind, p0, p1, p2, p3, p4, p5) == RC_SUCCESS ? out : NULL;
      }
      """
      |> String.trim()
    else
      ""
    end
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

  defp generated_color_defines(used_tokens \\ nil) do
    Constants.pebble_color_constants()
    |> Enum.sort_by(fn {name, _value} -> name end)
    |> Enum.filter(fn {name, _value} ->
      is_nil(used_tokens) or MapSet.member?(used_tokens, generated_color_macro(name))
    end)
    |> Enum.map_join("\n", fn {name, value} ->
      "#define #{generated_color_macro(name)} #{value}"
    end)
  end

  defp generated_render_op_defines(used_tokens \\ nil) do
    Kinds.draw_kinds()
    |> Enum.sort_by(fn {_kind, id} -> id end)
    |> Enum.filter(fn {kind, _id} ->
      is_nil(used_tokens) or MapSet.member?(used_tokens, render_op_macro(kind))
    end)
    |> Enum.map_join("\n", fn {kind, id} ->
      "#define #{render_op_macro(kind)} #{id}"
    end)
  end

  defp render_op_macro(kind) do
    macro = kind |> Atom.to_string() |> Util.macro_name()
    "ELMC_RENDER_OP_#{macro}"
  end

  defp fixed_magic_number_defines do
    fixed_magic_number_lines()
    |> Enum.map_join("\n", fn {macro, value} -> "#define #{macro} #{value}" end)
  end

  @spec generated_resource_slot_defines([String.t()], keyword() | map(), ElmEx.IR.t()) :: String.t()
  def generated_resource_slot_defines(chunks, opts, %ElmEx.IR{} = ir) do
    lines = Elmc.Backend.CCodegen.ResourceSlotMacros.define_lines(ir)

    filtered =
      if opts[:strip_dead_code] == false do
        lines
      else
        used_tokens = used_macro_tokens(Enum.join(chunks, "\n"))

        Enum.filter(lines, fn {macro, _value} ->
          MapSet.member?(used_tokens, macro)
        end)
      end

    filtered
    |> Enum.map_join("\n", fn {macro, value} -> "#define #{macro} #{value}" end)
  end

  defp used_fixed_magic_number_defines(used_tokens) do
    fixed_magic_number_lines()
    |> Enum.filter(fn {macro, _value} -> MapSet.member?(used_tokens, macro) end)
    |> Enum.map_join("\n", fn {macro, value} -> "#define #{macro} #{value}" end)
  end

  defp used_macro_tokens(source) do
    ~r/\bELMC_[A-Z0-9_]+\b/
    |> Regex.scan(source)
    |> Enum.map(fn [token] -> token end)
    |> MapSet.new()
  end

  @spec subscription_mask_literals() :: %{String.t() => String.t()}
  def subscription_mask_literals do
    fixed_magic_number_lines()
    |> Enum.filter(fn {name, _} -> String.starts_with?(name, "ELMC_SUBSCRIPTION_") end)
    |> Map.new()
  end

  @spec resolve_c_int_expr(String.t()) :: {:ok, integer()} | :error
  def resolve_c_int_expr(value) when is_binary(value) do
    case Map.get(magic_number_literals(), value) do
      nil ->
        case resolve_pebble_msg_macro(value) do
          {:ok, n} -> {:ok, n}
          :error -> :error
        end

      str ->
        parse_int_literal(str)
    end
  end

  defp resolve_pebble_msg_macro("ELMC_PEBBLE_MSG_" <> _ = macro) do
    tags = Process.get(:elmc_constructor_tags, %{})

    case Enum.find_value(tags, fn {name, tag} ->
           short = name |> String.split(".") |> List.last()
           expected = "ELMC_PEBBLE_MSG_" <> Elmc.Backend.Pebble.Util.macro_name(short)

           if expected == macro, do: tag
         end) do
      tag when is_integer(tag) -> {:ok, tag}
      _ -> :error
    end
  end

  defp resolve_pebble_msg_macro(_), do: :error

  @spec magic_number_literals() :: %{String.t() => String.t()}
  def magic_number_literals, do: Map.new(fixed_magic_number_lines())

  defp parse_int_literal(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, ""} -> {:ok, n}
      _ -> :error
    end
  end

  defp fixed_magic_number_lines do
    [
      {"ELMC_CONTEXT_STROKE_WIDTH", "1"},
      {"ELMC_CONTEXT_ANTIALIASED", "2"},
      {"ELMC_CONTEXT_STROKE_COLOR", "3"},
      {"ELMC_CONTEXT_FILL_COLOR", "4"},
      {"ELMC_CONTEXT_TEXT_COLOR", "5"},
      {"ELMC_CONTEXT_COMPOSITING_MODE", "6"},
      {"ELMC_UI_NODE_WINDOW_STACK", "1000"},
      {"ELMC_UI_NODE_WINDOW", "1001"},
      {"ELMC_UI_NODE_CANVAS_LAYER", "1002"},
      {"ELMC_BUTTON_BACK", "0"},
      {"ELMC_BUTTON_UP", "1"},
      {"ELMC_BUTTON_SELECT", "2"},
      {"ELMC_BUTTON_DOWN", "3"},
      {"ELMC_BUTTON_EVENT_PRESSED", "1"},
      {"ELMC_BUTTON_EVENT_RELEASED", "2"},
      {"ELMC_BUTTON_EVENT_LONG_PRESSED", "3"},
      {"ELMC_SUBSCRIPTION_SECOND_CHANGE", "1"},
      {"ELMC_SUBSCRIPTION_BUTTON_UP", "2"},
      {"ELMC_SUBSCRIPTION_BUTTON_SELECT", "4"},
      {"ELMC_SUBSCRIPTION_BUTTON_DOWN", "8"},
      {"ELMC_SUBSCRIPTION_ACCEL_TAP", "16"},
      {"ELMC_SUBSCRIPTION_BATTERY", "32"},
      {"ELMC_SUBSCRIPTION_CONNECTION", "64"},
      {"ELMC_SUBSCRIPTION_APPMESSAGE", "4096"},
      {"ELMC_SUBSCRIPTION_HOUR_CHANGE", "1024"},
      {"ELMC_SUBSCRIPTION_MINUTE_CHANGE", "2048"},
      {"ELMC_SUBSCRIPTION_FRAME_BASE", "8192"},
      {"ELMC_SUBSCRIPTION_BUTTON_RAW", "16384"},
      {"ELMC_SUBSCRIPTION_DAY_CHANGE", "65536"},
      {"ELMC_SUBSCRIPTION_MONTH_CHANGE", "131072"},
      {"ELMC_SUBSCRIPTION_YEAR_CHANGE", "262144"},
      {"ELMC_SUBSCRIPTION_BUTTON_LONG_UP", "128"},
      {"ELMC_SUBSCRIPTION_BUTTON_LONG_SELECT", "256"},
      {"ELMC_SUBSCRIPTION_BUTTON_LONG_DOWN", "512"},
      {"ELMC_SUBSCRIPTION_ACCEL_DATA", "32768"},
      {"ELMC_SUBSCRIPTION_APP_FOCUS", "524288"},
      {"ELMC_SUBSCRIPTION_BACKLIGHT", "16777216"},
      {"ELMC_SUBSCRIPTION_SCREEN_CHANGE", "33554432"},
      {"ELMC_SUBSCRIPTION_SPEAKER_FINISHED", "67108864"},
      {"ELMC_SUBSCRIPTION_COMPASS", "1048576"},
      {"ELMC_SUBSCRIPTION_DICTATION", "2097152"},
      {"ELMC_SUBSCRIPTION_UNOBSTRUCTED_AREA", "4194304"},
      {"ELMC_SUBSCRIPTION_ANIMATION_FINISHED", "8388608"},
      {"ELMC_SUBSCRIPTION_HEALTH", "2147483648LL"},
      {"ELMC_TEXT_ALIGN_LEFT", "0"},
      {"ELMC_TEXT_ALIGN_CENTER", "1"},
      {"ELMC_TEXT_ALIGN_RIGHT", "2"},
      {"ELMC_TEXT_OVERFLOW_WORD_WRAP", "0"},
      {"ELMC_TEXT_OVERFLOW_TRAILING_ELLIPSIS", "1"},
      {"ELMC_TEXT_OVERFLOW_FILL", "2"},
      {"ELMC_TEXT_OVERFLOW_SHIFT", "2"}
    ]
  end
end
