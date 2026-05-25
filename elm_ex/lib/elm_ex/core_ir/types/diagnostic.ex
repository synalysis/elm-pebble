defmodule ElmEx.CoreIR.Types.Diagnostic do
  @moduledoc false

  @type t :: %{
          required(:severity) => String.t(),
          required(:code) => String.t(),
          optional(:module) => String.t() | nil,
          optional(:function) => String.t() | nil,
          optional(:message) => String.t()
        }
end
