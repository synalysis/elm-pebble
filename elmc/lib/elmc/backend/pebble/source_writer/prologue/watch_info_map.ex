defmodule Elmc.Backend.Pebble.SourceWriter.Prologue.WatchInfoMap do
  @moduledoc false
  alias Elmc.Backend.Pebble.Util
  alias Elmc.Backend.Pebble.WatchInfoMap
  alias Elmc.Types, as: Types

  @spec body() :: Types.c_source()
  def body do
    """
    int64_t elmc_pebble_watch_color_to_elm_tag(int color) {
    #{switch_body("color", WatchInfoMap.colors(), "ELMC_PEBBLE_WATCH_COLOR", "UnknownColor")}
    }

    int64_t elmc_pebble_watch_model_to_elm_tag(int model) {
    #{switch_body("model", WatchInfoMap.models(), "ELMC_PEBBLE_WATCH_MODEL", "UnknownModel")}
    }

    """
  end

  @spec switch_body(String.t(), [{String.t(), String.t()}], String.t(), String.t()) :: String.t()
  defp switch_body(param, entries, elm_prefix, default_ctor) do
    cases =
      Enum.map_join(entries, "\n", fn {elm_ctor, sdk_enum} ->
        elm_macro = "#{elm_prefix}_#{Util.macro_name(elm_ctor)}"

        """
          #ifdef #{sdk_enum}
          #ifdef #{elm_macro}
            case #{sdk_enum}:
              return #{elm_macro};
          #endif
          #endif
        """
      end)

    default_macro = "#{elm_prefix}_#{Util.macro_name(default_ctor)}"

    """
      switch (#{param}) {
    #{cases}
        default:
    #ifdef #{default_macro}
          return #{default_macro};
    #else
          return 0;
    #endif
      }
    """
  end
end
