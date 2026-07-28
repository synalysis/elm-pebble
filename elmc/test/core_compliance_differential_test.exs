defmodule Elmc.CoreComplianceDifferentialTest do
  @moduledoc """
  Value oracle: elmx runtime vs elmc plan bytecode for pure helpers.

  elmx `CoreCompliance` is the reference implementation; elmc runs the same
  cases through the bytecode manifest (no host C link — avoids rc_track ABI drift).
  """

  use ExUnit.Case, async: false

  alias ElmEx.Frontend.Bridge
  alias ElmEx.IR.Lowerer
  alias Elmx.Backend.ElixirCodegen
  alias Elmx.IRDigest
  alias Elmx.Runtime.Loader, as: ElmxLoader
  alias Elmc.Backend.Bytecode.Loader

  @elmx_project Path.expand("../../elmx/test/fixtures/simple_project", __DIR__)
  @elmc_fixture Path.expand("fixtures/simple_project", __DIR__)

  # Bytecode-safe cases only. Zero-arity Dict/Set/Array CAFs and string ABI still
  # return nil from the bytecode loader — expand when those ABIs stabilize.
  # Maybe.Just: elmx uses {:Just, n}; elmc bytecode uses {:just, n}.
  @cases [
    {:foldSum, [[1, 2, 3]], [[1, 2, 3]], 6},
    {:tuplePairFirst, [7, 9], [7, 9], 7},
    {:maybeInc, [nil], [nil], 0},
    {:maybeInc, [{:"Just", 4}], [{:just, 4}], 5},
    {:modByNeg, [7], [7], 2},
    {:modByNeg, [-3], [-3], 2},
    {:first, [{11, 22}], [{11, 22}], 11},
    {:second, [{11, 22}], [{11, 22}], 22}
  ]

  setup_all do
    {:ok, project} = Bridge.load_project(@elmx_project)
    {:ok, ir0} = Lowerer.lower_project(project)
    mod = Enum.find(ir0.modules, &(&1.name == "CoreCompliance"))
    ir = %{ir0 | modules: [mod]}
    ir_sha256 = IRDigest.sha256(ir)

    assert {:ok, [compiled | _]} =
             ElixirCodegen.emit_project(ir, %{
               entry_module: "Main",
               mode: :library,
               ir_sha256: ir_sha256,
               user_module_names: ["CoreCompliance"]
             })

    assert {:ok, [entry | _]} = ElmxLoader.compile_modules([compiled])
    {:ok, elmx_module: entry.module}
  end

  @tag :slow
  test "elmx oracle agrees with elmc bytecode on shared pure helpers", %{elmx_module: elmx} do
    out_dir = Path.expand("tmp/core_compliance_differential", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@elmc_fixture, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false,
               plan_ir_mode: :primary,
               plan_ir_strict: false
             })

    for {name, elmx_args, elmc_args, expected} <- @cases do
      elmx_result = apply(elmx, String.to_atom("elmx_fn_CoreCompliance_#{name}"), elmx_args)
      assert elmx_result == expected

      assert {:ok, elmc_result} =
               Loader.run_manifest_entry(out_dir, {"CoreCompliance", Atom.to_string(name)},
                 params: elmc_args
               )

      assert elmc_result == expected,
             "elmc bytecode #{name}#{inspect(elmc_args)} expected #{expected}, got #{inspect(elmc_result)}"
    end
  end
end
