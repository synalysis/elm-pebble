defmodule ElmEx.CoreIR.Types.CoreIR do
  @moduledoc """
  Top-level `ElmEx.CoreIR` struct typing (re-export hub).
  """

  alias ElmEx.CoreIR.Types.{Diagnostic, Module}

  @type t :: %ElmEx.CoreIR{
          version: String.t(),
          modules: [Module.t() | Module.wire_t()],
          diagnostics: [Diagnostic.t() | Diagnostic.wire_t()],
          deterministic_sha256: String.t()
        }
end
