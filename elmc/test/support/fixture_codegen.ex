defmodule Elmc.Test.FixtureCodegen do
  @moduledoc false

  @fixtures_dir Path.expand("../fixtures", __DIR__)

  @elmx_excluded ~w(
    rc_track_2048_pebble_project
  )

  @elmx_known_failures ~w()

  @pebble_smoke_fixtures ~w(
    simple_project
    pebble_surface_project
  )

  @ts_derived_fixture "ts_derived_patterns_project"

  @spec fixtures_dir() :: String.t()
  def fixtures_dir, do: @fixtures_dir

  @spec fixture_dirs() :: [String.t()]
  def fixture_dirs do
    @fixtures_dir
    |> File.ls!()
    |> Enum.filter(fn name ->
      File.dir?(Path.join(@fixtures_dir, name)) and
        File.exists?(Path.join([@fixtures_dir, name, "elm.json"]))
    end)
    |> Enum.sort()
  end

  @spec elmx_fixture_dirs() :: [String.t()]
  def elmx_fixture_dirs do
    fixture_dirs()
    |> Enum.reject(&(&1 in @elmx_excluded))
  end

  @spec elmx_compile_fixture_dirs() :: [String.t()]
  def elmx_compile_fixture_dirs do
    elmx_fixture_dirs()
    |> Enum.reject(&(&1 in @elmx_known_failures))
  end

  @spec elmx_known_failures() :: [String.t()]
  def elmx_known_failures, do: @elmx_known_failures

  @spec pebble_smoke_fixtures() :: [String.t()]
  def pebble_smoke_fixtures, do: @pebble_smoke_fixtures

  @spec ts_derived_fixture() :: String.t()
  def ts_derived_fixture, do: @ts_derived_fixture

  @spec project_dir(String.t()) :: String.t()
  def project_dir(fixture_name), do: Path.join(@fixtures_dir, fixture_name)

  @spec compile_elmc!(String.t(), keyword()) :: :ok
  def compile_elmc!(fixture_name, opts \\ []) do
    project_dir = project_dir(fixture_name)
    out_dir = Keyword.get(opts, :out_dir, Path.join(System.tmp_dir!(), "elmc_fixture_#{fixture_name}"))

    File.rm_rf!(out_dir)

    case Elmc.compile(project_dir, %{
           out_dir: out_dir,
           strip_dead_code: false,
           entry_module: Keyword.get(opts, :entry_module, "Main")
         }) do
      {:ok, _} -> :ok
      {:error, reason} -> raise "elmc compile failed for #{fixture_name}: #{inspect(reason, limit: 8)}"
    end
  end

  @spec compile_elmx!(String.t(), keyword()) :: module()
  def compile_elmx!(fixture_name, opts \\ []) do
    project_dir = project_dir(fixture_name)
    entry_module = Keyword.get(opts, :entry_module, "Main")
    revision = Keyword.get(opts, :revision, "fixture-" <> fixture_name)

    case Elmx.compile_in_memory(project_dir, %{
           entry_module: entry_module,
           strip_dead_code: false,
           mode: :library,
           revision: revision
         }) do
      {:ok, %{entry_module: mod}} ->
        mod

      {:error, reason} ->
        raise "elmx compile failed for #{fixture_name}: #{inspect(reason, limit: 8)}"
    end
  end

  @spec run_elmx_main!(String.t(), keyword()) :: String.t()
  def run_elmx_main!(fixture_name, opts \\ []) do
    mod = compile_elmx!(fixture_name, opts)
    entry_module = Keyword.get(opts, :entry_module, "Main")

    mod
    |> apply(:"elmx_fn_#{entry_module}_main", [])
    |> to_string()
  end
end
