defmodule Elmc.PlanManifestExecutionSmokeTest do
  @moduledoc """
  Smoke-test bytecode manifest execution on strict templates that exercise
  guarded patterns (tuple/ctor `bool_and`) and list recursion.
  """

  use ExUnit.Case, async: false

  alias Elmc.Backend.Bytecode.Loader
  alias Elmc.TestSupport.TemplateCompile

  @moduletag :plan_surface
  @moduletag :slow

  @templates ~w(watchface_poke_battle game_basic game_2048)

  for template <- @templates do
    @tag template: template

    test "bytecode manifest init runs for #{template}", %{template: template} do
      out_dir = Path.expand("tmp/plan_manifest_smoke/#{template}", __DIR__)
      File.rm_rf!(out_dir)

      assert {:ok, _result} =
               TemplateCompile.compile_watch_template(template,
                 plan_ir_mode: :primary,
                 plan_ir_strict: true,
                 out_dir: out_dir
               )

      task =
        Task.async(fn ->
          Loader.run_manifest_entry(out_dir, {"Main", "init"}, params: init_params(template))
        end)

      result =
        case Task.yield(task, 15_000) || Task.shutdown(task, :brutal_kill) do
          {:ok, value} -> value
          nil -> flunk("bytecode init for #{template} timed out")
        end

      assert match?({:ok, {:tuple2, _, _}}, result),
             "expected (Model, Cmd) tuple from init, got #{inspect(result)}"
    end
  end

  test "poke battle update runs guarded tuple/msg patterns from manifest" do
    out_dir = Path.expand("tmp/plan_manifest_smoke/poke_update", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _result} =
             TemplateCompile.compile_watch_template("watchface_poke_battle",
               plan_ir_mode: :primary,
               plan_ir_strict: true,
               out_dir: out_dir
             )

    {:ok, {:tuple2, model, _cmd}} =
      Loader.run_manifest_entry(out_dir, {"Main", "init"},
        params: [{:record, [144, 168, 0, 0, 0]}]
      )

    task =
      Task.async(fn ->
        Loader.run_manifest_entry(out_dir, {"Main", "update"}, params: [1, model])
      end)

    case Task.yield(task, 15_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, {:tuple2, _updated, _}}} -> :ok
      {:ok, other} -> flunk("unexpected update result: #{inspect(other)}")
      nil -> flunk("bytecode update for poke_battle timed out")
    end
  end

  test "list range map runs list_cursor_map from compiled manifest" do
    source = """
    module Main exposing (scaledRange)

    scaledRange : List Int
    scaledRange =
        List.map (\\i -> i * 2) (List.range 0 3)
    """

    project_dir = Path.expand("tmp/plan_manifest_smoke/list_cursor", __DIR__)
    out_dir = Path.expand("tmp/plan_manifest_smoke/list_cursor_out", __DIR__)
    File.rm_rf!(project_dir)
    File.rm_rf!(out_dir)
    File.mkdir_p!(Path.join(project_dir, "src"))
    File.write!(Path.join(project_dir, "src/Main.elm"), source)

    File.write!(
      Path.join(project_dir, "elm.json"),
      File.read!(Path.expand("fixtures/simple_project/elm.json", __DIR__))
    )

    assert {:ok, _} =
             Elmc.compile(project_dir, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    assert {:ok, values} =
             Loader.run_manifest_entry(out_dir, {"Main", "scaledRange"}, params: [])

    assert values == [0, 2, 4, 6]
  end

  defp init_params("game_2048"), do: [{:record, [144, 168, 0]}]
  defp init_params("game_basic"), do: [{:record, [144, 168]}]
  defp init_params(_template), do: [{:record, [144, 168, 0, 0, 0]}]
end
