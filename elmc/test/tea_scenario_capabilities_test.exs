defmodule Elmc.TeaScenarioCapabilitiesTest do
  @moduledoc """
  Header capability detection must see `ELMC_PEBBLE_HAS_MSG_*` feature macros.

  Without that, TEA playbooks silently drop FromPhone / datetime steps and
  ownership/valgrind smokes never exercise boxed payload dispatch.
  """

  use ExUnit.Case, async: true

  alias Elmc.TestSupport.TeaScenario

  test "capabilities recognize HAS_MSG feature macros" do
    path = Path.join(System.tmp_dir!(), "tea-caps-#{System.unique_integer([:positive])}.h")

    try do
      File.write!(path, """
      enum {
        ELMC_PEBBLE_MSG_CURRENTDATETIME = 1,
        ELMC_PEBBLE_MSG_FROMPHONE = 10,
        ELMC_PEBBLE_MSG_BATTERYLEVELCHANGED = 2
      };
      #define ELMC_PEBBLE_HAS_MSG_CURRENTDATETIME 1
      #define ELMC_PEBBLE_HAS_MSG_FROMPHONE 1
      #define ELMC_PEBBLE_HAS_MSG_BATTERYLEVELCHANGED 1
      """)

      caps = TeaScenario.capabilities(path)
      assert caps.has_current_datetime
      assert caps.has_from_phone
      assert caps.has_battery
    after
      File.rm(path)
    end
  end
end
