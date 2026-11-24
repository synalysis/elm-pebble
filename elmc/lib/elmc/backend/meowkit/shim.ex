defmodule Elmc.Backend.Meowkit.Shim do
  @moduledoc """
  Compatibility wrapper. Handheld artifacts now live in
  `Elmc.Backend.Handheld.Artifacts`.
  """

  alias Elmc.Backend.Handheld
  alias Elmc.Backend.Handheld.Artifacts

  @spec write(String.t(), [String.t()]) :: :ok | {:error, term()}
  def write(out_dir, targets) when is_binary(out_dir) and is_list(targets) do
    Artifacts.write(out_dir, %{target: Enum.join(targets, ",")})
  end

  @spec targets(map()) :: [String.t()]
  def targets(opts) when is_map(opts), do: Handheld.targets(opts)
end
