defmodule Elmc.CLI.Types.Manifest do
  @moduledoc """
  JSON manifest maps emitted by `elmc manifest` (`Elmc.CLI.build_manifest/2`).
  """

  @type dependency_status :: String.t()

  @typedoc """
  One dependency compatibility row. Runtime keys: `"package"`, `"status"`, `"reason_code"`, `"message"`.
  """
  @type dependency_compatibility_row :: %{
          optional(atom()) => String.t(),
          optional(String.t()) => String.t()
        }

  @typedoc """
  Manifest body. Runtime keys: `"supported_packages"`, `"excluded_packages"`,
  `"modules_detected"`, `"dependency_compatibility"`.
  """
  @type t :: %{
          optional(atom()) => String.t() | [String.t()] | [dependency_compatibility_row()],
          optional(String.t()) => String.t() | [String.t()] | [dependency_compatibility_row()]
        }

  @type wire_map :: t()
end
