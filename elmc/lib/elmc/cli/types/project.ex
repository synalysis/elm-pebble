defmodule Elmc.CLI.Types.Project do
  @moduledoc """
  Frontend project shape consumed by CLI manifest generation.
  """

  alias ElmEx.Frontend.Project, as: FrontendProject

  @type t :: FrontendProject.t()
end
