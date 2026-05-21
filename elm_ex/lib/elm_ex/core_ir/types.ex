defmodule ElmEx.CoreIR.Types do
  @moduledoc false

  @type normalized_module :: %{
          required(String.t()) => String.t() | [String.t()] | map() | [map()]
        }

  @type normalized_value ::
          map()
          | [normalized_value()]
          | String.t()
          | number()
          | boolean()
          | nil
          | atom()

  @type normalized_diagnostic :: %{
          required(String.t()) => String.t() | nil
        }
end
