defmodule Elmc.CLI.Types.Project do
  @moduledoc """
  Minimal frontend project shape consumed by CLI manifest generation.
  """

  @type module_entry :: %{
          required(:name) => String.t(),
          optional(atom()) => term(),
          optional(String.t()) => term()
        }

  @type t :: %{
          required(:modules) => [module_entry()],
          optional(atom()) => term(),
          optional(String.t()) => term()
        }
end
