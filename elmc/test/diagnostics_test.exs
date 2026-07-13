defmodule Elmc.DiagnosticsTest do
  use ExUnit.Case, async: true

  alias Elmc.Diagnostics

  test "errors_only keeps blocking severities" do
    diagnostics = [
      %{"severity" => "info", "message" => "ok"},
      %{"severity" => "warning", "message" => "warn"},
      %{"severity" => "error", "message" => "fail"}
    ]

    assert [%{"severity" => "error", "message" => "fail"}] = Diagnostics.errors_only(diagnostics)
  end

  test "partition splits blocking and informational diagnostics" do
    diagnostics = [
      %{"severity" => "info"},
      %{"severity" => "error"}
    ]

    assert {[%{"severity" => "error"}], [%{"severity" => "info"}]} =
             Diagnostics.partition(diagnostics)
  end

  test "blocking_from_sources flattens and filters errors" do
    assert [%{"severity" => "error"}] =
             Diagnostics.blocking_from_sources(
               layout: [%{"severity" => "warning"}],
               debug: [%{"severity" => "error"}]
             )
  end
end
