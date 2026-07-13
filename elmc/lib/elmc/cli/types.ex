defmodule Elmc.CLI.Types do
  @moduledoc """
  Typed results returned by in-process `Elmc.CLI` project runners.
  """

  alias Elmc.CLI.Types.{Manifest, Project}
  alias Elmc.Types, as: RootTypes

  @type cli_diagnostic :: RootTypes.cli_diagnostic()

  @type run_status :: :ok | :error

  @type project_run :: %{
          required(:status) => run_status(),
          required(:output) => String.t(),
          required(:warnings) => [cli_diagnostic()]
        }

  @type manifest_run :: %{
          required(:status) => run_status(),
          required(:output) => String.t(),
          required(:warnings) => [cli_diagnostic()],
          required(:manifest) => Manifest.wire_map() | nil
        }

  @type project_manifest :: Manifest.t()
  @type dependency_compatibility_row :: Manifest.dependency_compatibility_row()
  @type manifest_project :: Project.t()

  @type frontend_bridge_error :: RootTypes.frontend_bridge_error()

  @type compile_error :: RootTypes.compile_error()

  @type compile_result :: RootTypes.compile_result()
end
