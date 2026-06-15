defmodule Elmc.Backend.Pebble.SourceWriter.Prologue.TraceMacros do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec body() :: Types.c_source()
  def body do
    """
    #if defined(ELMC_PEBBLE_TRACE_FUNCTIONS) && defined(ELMC_PEBBLE_PLATFORM)
    #define ELMC_PEBBLE_GENERATED_TRACE_ENTER(name) app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, "g+%d", __LINE__)
    #define ELMC_PEBBLE_GENERATED_TRACE_EXIT(name) app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, "g-%d", __LINE__)
    #define ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT(name, value) \\
      do { \\
        int elmc_pebble_trace_rc__ = (value); \\
        app_log(APP_LOG_LEVEL_INFO, __FILE_NAME__, __LINE__, "g-%d rc=%d", __LINE__, elmc_pebble_trace_rc__); \\
        return elmc_pebble_trace_rc__; \\
      } while (0)
    #else
    #define ELMC_PEBBLE_GENERATED_TRACE_ENTER(name) do { } while (0)
    #define ELMC_PEBBLE_GENERATED_TRACE_EXIT(name) do { } while (0)
    #define ELMC_PEBBLE_GENERATED_TRACE_RETURN_INT(name, value) return (value)
    #endif

    """
  end
end
