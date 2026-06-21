defmodule Elmc.DebugUsageTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.DebugUsage

  @fixture Path.expand("fixtures/rc_track_debug_project", __DIR__)

  defp compile_opts(overrides) do
    out_dir =
      Path.join(
        System.tmp_dir!(),
        "elmc_debug_usage_#{System.unique_integer([:positive])}"
      )

    File.rm_rf!(out_dir)

    Map.merge(
      %{
        out_dir: out_dir,
        entry_module: "RcTrackDebugProbe",
        strip_dead_code: false,
        prod: true,
        debug_usage_policy: :error
      },
      Map.new(overrides)
    )
  end

  test "prod mode rejects Debug.log, Debug.todo, and Debug.toString" do
    opts = compile_opts(%{})

    assert {:error, {:compile_diagnostics, diagnostics}} =
             Elmc.compile(@fixture, opts)

    codes = Enum.map(diagnostics, & &1["code"])
    assert "debug_usage_not_allowed" in codes
    assert Enum.count(codes, &(&1 == "debug_usage_not_allowed")) == 3
    assert Enum.all?(diagnostics, &(&1["source"] == "elmc/debug"))
  end

  test "prod warn policy succeeds and reports debug_usage_in_build diagnostics" do
    opts = compile_opts(%{debug_usage_policy: :warn})

    assert {:ok, result} = Elmc.compile(@fixture, opts)
    diagnostics = Map.get(result, :debug_usage_diagnostics, [])
    assert length(diagnostics) == 3
    assert Enum.all?(diagnostics, &(&1["severity"] == "warning"))
    assert Enum.all?(diagnostics, &(&1["code"] == "debug_usage_in_build"))
  end

  test "non-prod mode allows Debug usage and emits debug C support" do
    opts = compile_opts(%{prod: false})

    assert {:ok, _} = Elmc.compile(@fixture, opts)

    generated = File.read!(Path.join(opts.out_dir, "c/elmc_generated.c"))

    assert generated =~ "elmc_debug_union_ctor_name"
    assert generated =~ "switch (tag)"
    assert generated =~ "elmc_agent_generated_probe"
  end

  test "prod mode omits debug ctor table cases and agent probes from generated C" do
    opts = compile_opts(%{prod: false})
    assert {:ok, _} = Elmc.compile(@fixture, opts)

    prod_opts = %{opts | prod: true, debug_usage_policy: :warn}
    assert {:ok, _} = Elmc.compile(@fixture, prod_opts)

    generated = File.read!(Path.join(prod_opts.out_dir, "c/elmc_generated.c"))
    refute generated =~ "elmc_agent_generated_probe"
    assert generated =~ "(void)tag;"
    assert generated =~ "return NULL;"
  end

  test "collect finds canonical Debug targets in IR" do
    {:ok, project} = Elmc.check(@fixture)
    {:ok, ir} = ElmEx.IR.Lowerer.lower_project(project)

    usages = DebugUsage.collect(ir)
    targets = Enum.map(usages, & &1.target) |> Enum.sort()

    assert targets == Enum.sort(["Debug.log", "Debug.todo", "Debug.toString"])
  end
end
