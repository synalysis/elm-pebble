defmodule ElmEx.IR.Types.IR do
  @moduledoc """
  Top-level `ElmEx.IR` struct typing (re-export hub).
  """

  alias ElmEx.IR.Types.{Diagnostic, Module}

  @type t :: %ElmEx.IR{
          modules: [Module.t()],
          diagnostics: [Diagnostic.t() | Diagnostic.wire_map()]
        }
end
