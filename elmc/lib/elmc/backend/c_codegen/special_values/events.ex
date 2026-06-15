defmodule Elmc.Backend.CCodegen.SpecialValues.Events do
  @moduledoc false

  alias Elmc.Backend.CCodegen.SpecialValues.Core

  @spec special_value_from_target(String.t(), [term()]) :: term()
  defdelegate special_value_from_target(target, args), to: Core
end
