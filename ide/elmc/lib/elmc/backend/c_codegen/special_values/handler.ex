defmodule Elmc.Backend.CCodegen.SpecialValues.Handler do
  @moduledoc """
  Contract for `special_value_from_target/2` handler modules chained by `Dispatcher`.
  """

  alias Elmc.Backend.CCodegen.Types

  @callback special_value_from_target(String.t(), Types.special_value_args()) ::
              Types.special_value_result()
end
