defmodule Elmx.TemplateCompileGateTest do
  @moduledoc """
  Tag marker for template compile gates.

  Full priv-template sweep: `ELMX_TEMPLATE_COMPILE_GATE=1 mix test --only template_compile_gate` in `ide/`.
  Init/execute smoke: `ELMX_TEMPLATE_CORPUS=1 mix test --only compiled_elixir_corpus` in `ide/`.
  """

  use ExUnit.Case, async: false

  @tag :template_compile_gate
  test "template compile gate runs in ide corpus tests" do
    assert true
  end
end
