defmodule Ide.CompanionProtocolRuntimeRepruneTest do
  use ExUnit.Case, async: true

  alias Elmc.Runtime.Generator, as: RuntimeGenerator
  alias Ide.CompanionProtocolGenerator

  @list_helper_def ~r/ElmcValue \*elmc_list_from_int_array\(const elmc_int_t \*items, int count\) \{/
  @record_helper_def ~r/ElmcValue \*elmc_record_new_take\(int field_count, const char \*\*field_names, ElmcValue \*\*field_values\) \{/
  @dict_helper_def ~r/ElmcValue \*elmc_dict_from_list\(ElmcValue \*items\) \{/

  test "repruned runtime includes list helper referenced by companion protocol C" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-reprune-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")
    minimal_c = Path.join(tmp, "elmc/c/minimal.c")
    runtime_dir = Path.join(tmp, "elmc/runtime")

    try do
      File.mkdir_p!(Path.dirname(types))
      File.mkdir_p!(Path.dirname(minimal_c))
      File.mkdir_p!(runtime_dir)

      File.write!(types, """
      module Companion.Types exposing (PhoneToWatch(..), WatchToPhone(..))

      type WatchToPhone
          = RequestFigure

      type PhoneToWatch
          = ProvidePiece Int (List Int)
      """)

      File.write!(minimal_c, """
      #include "elmc_runtime.h"

      void companion_protocol_runtime_reprune_probe(void) {
        (void)elmc_new_int(0);
      }
      """)

      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)

      assert :ok =
               RuntimeGenerator.write_runtime(runtime_dir,
                 prune_from_dir: Path.join(tmp, "elmc"),
                 pebble_int32: true
               )

      refute File.read!(Path.join(runtime_dir, "elmc_runtime.c")) =~ @list_helper_def

      assert :ok =
               RuntimeGenerator.write_runtime(runtime_dir,
                 prune_from_dir: tmp,
                 pebble_int32: true
               )

      assert File.read!(Path.join(runtime_dir, "elmc_runtime.c")) =~ @list_helper_def
    after
      File.rm_rf(tmp)
    end
  end

  test "repruned runtime includes record and dict helpers referenced by companion protocol C" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "elm-pebble-protocol-composite-reprune-#{System.unique_integer([:positive])}"
      )

    types = Path.join(tmp, "Types.elm")
    header = Path.join(tmp, "generated/companion_protocol.h")
    source = Path.join(tmp, "generated/companion_protocol.c")
    js = Path.join(tmp, "pkjs/companion-protocol.js")
    minimal_c = Path.join(tmp, "elmc/c/minimal.c")
    runtime_dir = Path.join(tmp, "elmc/runtime")

    try do
      File.mkdir_p!(Path.dirname(types))
      File.mkdir_p!(Path.dirname(minimal_c))
      File.mkdir_p!(runtime_dir)

      File.write!(types, """
      module Companion.Types exposing (PhoneToWatch(..), Point, WatchToPhone(..))

      type alias Point =
          { x : Int, y : Int }

      type WatchToPhone
          = RequestFigure

      type PhoneToWatch
          = SetOrigin Point
          | SetLabels (Dict String Int)
      """)

      File.write!(minimal_c, """
      #include "elmc_runtime.h"

      void companion_protocol_runtime_reprune_probe(void) {
        (void)elmc_new_int(0);
      }
      """)

      assert :ok = CompanionProtocolGenerator.generate(types, header, source, js)

      assert :ok =
               RuntimeGenerator.write_runtime(runtime_dir,
                 prune_from_dir: Path.join(tmp, "elmc"),
                 pebble_int32: true
               )

      runtime_source = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))
      refute runtime_source =~ @record_helper_def
      refute runtime_source =~ @dict_helper_def

      assert :ok =
               RuntimeGenerator.write_runtime(runtime_dir,
                 prune_from_dir: tmp,
                 pebble_int32: true
               )

      runtime_source = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))
      assert runtime_source =~ @record_helper_def
      assert runtime_source =~ @dict_helper_def
    after
      File.rm_rf(tmp)
    end
  end
end
