defmodule Elmc.Backend.Pebble.MsgCodegen.TickArity do
  @moduledoc false

  alias Elmc.Backend.Pebble.Types

  @spec dispatch_line(boolean()) :: Types.c_source()
  def dispatch_line(true) do
    "  if (elmc_msg_constructor_arity(tag) > 0) return elmc_pebble_dispatch_tag_value(app, tag, elmc_current_second());"
  end

  def dispatch_line(false), do: ""

  @spec current_second_helper(boolean()) :: Types.c_source()
  def current_second_helper(true) do
    """
    #ifdef ELMC_PEBBLE_PLATFORM
    extern long time(long *timer);

    static int elmc_current_second(void) {
      long now = time(NULL);
      if (now == -1L) return 0;
      return (int)(now % 60);
    }
    #else
    static int elmc_current_second(void) {
      time_t now = time(NULL);
      if (now == (time_t)-1) return 0;
      return (int)(now % 60);
    }
    #endif
    """
  end

  def current_second_helper(false), do: ""

  @spec constructor_arity_fn(boolean(), Types.c_source()) :: Types.c_source()
  def constructor_arity_fn(true, msg_constructor_arity_cases) do
    """
    static int elmc_msg_constructor_arity(elmc_int_t tag) {
      switch (tag) {
    #{msg_constructor_arity_cases}
        default: return 0;
      }
    }
    """
  end

  def constructor_arity_fn(false, _msg_constructor_arity_cases), do: ""
end
