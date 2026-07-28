defmodule Elmc.RuntimePruneCellPreambleTest do
  use ExUnit.Case, async: false

  @moduletag :sequential

  test "pruned runtime keeps cell typedefs and alloc macros in the preamble" do
    out_dir = Path.expand("tmp/runtime_prune_cell_preamble", __DIR__)
    refs_dir = Path.join(out_dir, "refs")
    runtime_dir = Path.join(out_dir, "runtime")

    File.rm_rf!(out_dir)
    File.mkdir_p!(refs_dir)

    # Touch the core allocators so prune keeps list/maybe/tuple paths that need cell types.
    File.write!(Path.join(refs_dir, "elmc_generated.c"), """
    #include "elmc_runtime.h"

    RC uses_core_cells(ElmcValue **out, ElmcValue *head, ElmcValue *tail, ElmcValue *just) {
      ElmcValue *list = NULL;
      ElmcValue *maybe = NULL;
      ElmcValue *pair = NULL;
      RC Rc = elmc_list_cons(&list, head, tail);
      if (Rc != RC_SUCCESS) return Rc;
      Rc = elmc_maybe_just(&maybe, just);
      if (Rc != RC_SUCCESS) {
        elmc_release(list);
        return Rc;
      }
      Rc = elmc_tuple2(&pair, list, maybe);
      elmc_release(list);
      elmc_release(maybe);
      if (Rc != RC_SUCCESS) return Rc;
      *out = pair;
      return RC_SUCCESS;
    }
    """)

    assert :ok = Elmc.Runtime.Generator.write_runtime(runtime_dir, prune_from_dir: refs_dir)

    runtime = File.read!(Path.join(runtime_dir, "elmc_runtime.c"))

    assert runtime =~ "} ElmcListCell;"
    assert runtime =~ "} ElmcMaybeCell;"
    assert runtime =~ "} ElmcTuple2Cell;"
    assert runtime =~ "ELMC_MAYBE_CELL_SCALAR"
    assert runtime =~ "ELMC_EMPTY_STRING"
    assert runtime =~ "ELMC_MAYBE_NOTHING"
    assert runtime =~ "ELMC_EMPTY_INT_LIST"
    assert runtime =~ "#define elmc_alloc("
    assert runtime =~ "ELMC_RC_TRACK_REGISTER"

    # Typedefs/macros must stay in the prune preamble (before any kept function body).
    typedef_idx = :binary.match(runtime, "} ElmcListCell;") |> elem(0)

    first_fn_idx =
      Enum.find_value(
        [
          "static int elmc_list_cell_release(",
          "static ElmcValue *elmc_alloc_impl(",
          "RC elmc_list_cons(",
          "RC elmc_maybe_just(",
          "RC elmc_tuple2("
        ],
        fn needle ->
          case :binary.match(runtime, needle) do
            {idx, _} -> idx
            :nomatch -> nil
          end
        end
      )

    assert is_integer(first_fn_idx)
    assert typedef_idx < first_fn_idx

    cc = System.find_executable("cc")
    if is_nil(cc), do: flunk("cc not available")

    object = Path.join(out_dir, "runtime_cell_preamble.o")

    {out, code} =
      System.cmd(
        cc,
        [
          "-c",
          "-std=c99",
          "-Wall",
          "-Wextra",
          "-Werror",
          "-include",
          Path.expand("support/elmc_host_stubs.h", __DIR__),
          "-I",
          runtime_dir,
          "-DELMC_RC_TRACK=0",
          Path.join(runtime_dir, "elmc_runtime.c"),
          "-o",
          object
        ],
        stderr_to_stdout: true
      )

    assert code == 0, out
  end
end
