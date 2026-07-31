defmodule Elmc.TestSupport.ElmJson do
  @moduledoc """
  Valid Elm 0.19.1 application `elm.json` maps for test/probe projects.

  Always includes `test-dependencies` and `elm/json` so official `elm make`
  does not hang (missing `test-dependencies` triggers an infinite CPU loop).
  """

  @default_core_version "1.0.5"
  # Match templates / simple_project pins; Bridge also vendors this under
  # ide/priv/internal_packages/elm-json for CI without ~/.elm.
  @default_json_version "1.1.3"
  @default_elm_version "0.19.1"

  @type source_directories :: [String.t()]
  @type dependency_map :: %{String.t() => String.t()}

  @doc """
  Returns a valid application `elm.json` map.

  ## Options

    * `:source_directories` — default `["src"]`
    * `:direct` — extra direct dependencies merged with defaults
    * `:indirect` — indirect dependency map (default `%{}`)
  """
  @spec minimal_application(keyword()) :: map()
  def minimal_application(opts \\ []) do
    source_directories = Keyword.get(opts, :source_directories, ["src"])

    direct =
      %{"elm/core" => @default_core_version, "elm/json" => @default_json_version}
      |> Map.merge(Map.new(Keyword.get(opts, :direct, %{})))

    indirect = Map.new(Keyword.get(opts, :indirect, %{}))

    %{
      "type" => "application",
      "source-directories" => source_directories,
      "elm-version" => @default_elm_version,
      "dependencies" => %{"direct" => direct, "indirect" => indirect},
      "test-dependencies" => %{"direct" => %{}, "indirect" => %{}}
    }
  end

  @doc "JSON-encoded `minimal_application/1` with trailing newline."
  @spec minimal_application_json(keyword()) :: String.t()
  def minimal_application_json(opts \\ []) do
    opts |> minimal_application() |> Jason.encode!(pretty: true) |> Kernel.<>("\n")
  end

  @doc "Writes a valid probe `elm.json` at `path`."
  @spec write!(Path.t(), keyword()) :: :ok
  def write!(path, opts \\ []) when is_binary(path) do
    :ok = File.write!(path, minimal_application_json(opts))
  end

  @doc """
  Writes `Main.elm` and `elm.json` under `project_dir`, creating `src/` when needed.

  Registers `on_exit` cleanup unless `:keep_on_exit` is true.
  """
  @spec write_probe_project!(Path.t(), String.t(), keyword()) :: :ok
  def write_probe_project!(project_dir, source, opts \\ [])
      when is_binary(project_dir) and is_binary(source) do
    source_root = Keyword.get(opts, :source_root, "src")
    rel_path = Keyword.get(opts, :rel_path, "Main.elm")
    keep? = Keyword.get(opts, :keep_on_exit, false)

    File.rm_rf!(project_dir)
    File.mkdir_p!(Path.join(project_dir, source_root))
    source_path = Path.join([project_dir, source_root, rel_path])
    File.write!(source_path, source)

    elm_json_opts =
      opts
      |> Keyword.take([:source_directories, :direct, :indirect])
      |> Keyword.put_new(:source_directories, [source_root])

    write!(Path.join(project_dir, "elm.json"), elm_json_opts)

    unless keep? do
      ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(project_dir) end)
    end

    :ok
  end
end
