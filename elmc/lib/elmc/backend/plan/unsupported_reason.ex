defmodule Elmc.Backend.Plan.UnsupportedReason do
  @moduledoc false

  alias Elmc.Backend.CCodegen.UnsupportedSurface

  @spec lookup(String.t(), String.t()) :: map() | nil
  def lookup(module, name) when is_binary(module) and is_binary(name) do
    reasons = Process.get(:elmc_plan_unsupported_reasons, %{})

    Map.get(reasons, {module, name}) ||
      Enum.find_value(reasons, fn
        {{^module, fn_name}, meta} when is_binary(fn_name) and is_map(meta) ->
          if String.starts_with?(fn_name, name <> "_"), do: meta, else: nil

        _ ->
          nil
      end)
  end

  @spec format(atom() | map() | tuple() | nil) :: String.t()
  defdelegate format(reason), to: UnsupportedSurface, as: :format_plan_reason
end
