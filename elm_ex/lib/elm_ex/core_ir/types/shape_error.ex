defmodule ElmEx.CoreIR.Types.ShapeError do
  @moduledoc """
  Structural validation errors from `ElmEx.CoreIR.Validate.validate_shape/1`.
  """

  @type path_segment :: String.t() | non_neg_integer()

  alias ElmEx.CoreIR.Types

  @type t :: %{
          required(:code) => String.t(),
          required(:message) => String.t(),
          required(:path) => [path_segment()],
          optional(:op) => String.t(),
          optional(atom()) => Types.wire_input(),
          optional(String.t()) => Types.wire_input()
        }
end
