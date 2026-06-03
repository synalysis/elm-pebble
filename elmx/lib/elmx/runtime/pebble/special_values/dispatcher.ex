defmodule Elmx.Runtime.Pebble.SpecialValues.Dispatcher do
  @moduledoc false

  alias Elmx.Types

  @callback rewrite(String.t(), Types.ir_arg_list()) :: Types.dispatch_result()
end
