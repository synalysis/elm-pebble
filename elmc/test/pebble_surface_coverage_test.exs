defmodule Elmc.PebbleSurfaceCoverageTest do
  use ExUnit.Case

  @fixture_main Path.expand("fixtures/pebble_surface_project/src/Main.elm", __DIR__)
  @fixture_project Path.expand("fixtures/pebble_surface_project", __DIR__)

  @api_modules %{
    "Pebble.Accel" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Accel.elm", __DIR__),
    "Pebble.Button" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Button.elm", __DIR__),
    "Pebble.Cmd" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Cmd.elm", __DIR__),
    "Pebble.Events" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Events.elm", __DIR__),
    "Pebble.Frame" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Frame.elm", __DIR__),
    "Pebble.Health" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Health.elm", __DIR__),
    "Pebble.Light" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Light.elm", __DIR__),
    "Pebble.Log" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Log.elm", __DIR__),
    "Pebble.Storage" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Storage.elm", __DIR__),
    "Pebble.System" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/System.elm", __DIR__),
    "Pebble.Time" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Time.elm", __DIR__),
    "Pebble.Vibes" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Vibes.elm", __DIR__),
    "Pebble.Wakeup" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/Wakeup.elm", __DIR__),
    "Pebble.WatchInfo" =>
      Path.expand("../../packages/elm-pebble/elm-watch/src/Pebble/WatchInfo.elm", __DIR__)
  }

  test "surface fixture coverage stays in sync with Pebble APIs" do
    covered = covered_functions_from_fixture(@fixture_main)
    expected = expected_functions_from_modules(@api_modules)

    missing = MapSet.difference(expected, covered) |> Enum.sort()
    extra = MapSet.difference(covered, expected) |> Enum.sort()

    assert missing == [],
           """
           surface fixture is missing Pebble API coverage:
           #{Enum.map_join(missing, "\n", &"  - #{&1}")}
           """

    assert extra == [],
           """
           surface fixture has stale coverage entries:
           #{Enum.map_join(extra, "\n", &"  - #{&1}")}
           """
  end

  test "surface fixture compiles and exercises parse helpers" do
    out_dir = Path.expand("tmp/pebble_surface_project", __DIR__)
    File.rm_rf!(out_dir)

    assert {:ok, _} =
             Elmc.compile(@fixture_project, %{
               out_dir: out_dir,
               entry_module: "Main",
               strip_dead_code: false
             })

    generated_c = Path.join(out_dir, "c/elmc_generated.c")
    generated_source = File.read!(generated_c)
    pebble_source = File.read!(Path.join(out_dir, "c/elmc_pebble.c"))

    assert String.contains?(generated_source, "elmc_string_to_int(")
    assert String.contains?(generated_source, "elmc_string_to_float(")
    assert String.contains?(pebble_source, "elmc_current_second()")
    refute String.contains?(pebble_source, "elmc_now_millis")
  end

  defp covered_functions_from_fixture(path) do
    path
    |> File.read!()
    |> then(
      &Regex.scan(~r/"(Pebble\.[A-Za-z0-9_]+\.[a-z][A-Za-z0-9_]*)"/, &1, capture: :all_but_first)
    )
    |> List.flatten()
    |> MapSet.new()
  end

  defp expected_functions_from_modules(module_paths) do
    module_paths
    |> Enum.flat_map(fn {module_name, path} ->
      path
      |> exported_functions()
      |> Enum.map(&"#{module_name}.#{&1}")
    end)
    |> MapSet.new()
  end

  defp exported_functions(path) do
    path
    |> File.read!()
    |> strip_block_comments()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&Regex.match?(~r/^[a-z][A-Za-z0-9_]*\s*:/, &1))
    |> Enum.map(fn line ->
      [name | _] = String.split(line, ":")
      String.trim(name)
    end)
  end

  defp strip_block_comments(source) do
    Regex.replace(~r/\{-[\s\S]*?-\}/u, source, "")
  end
end
