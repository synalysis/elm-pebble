defmodule Elmc.CLI.Types do
  @moduledoc """
  Typed results returned by in-process `Elmc.CLI` project runners.
  """

  @type cli_diagnostic :: map()

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
          required(:manifest) => map() | nil
        }
end
