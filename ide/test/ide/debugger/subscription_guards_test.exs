defmodule Ide.Debugger.SubscriptionGuardsTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeSurfaces
  alias Ide.Debugger.SubscriptionGuards

  test "truthy? understands Elm Maybe constructors" do
    assert SubscriptionGuards.truthy?(%{"ctor" => "Just", "args" => [1]})
    refute SubscriptionGuards.truthy?(%{"ctor" => "Nothing", "args" => []})
  end

  test "satisfied? checks field_truthy guards against runtime model fields" do
    state =
      RuntimeSurfaces.default_watch()
      |> Map.put(:watch, RuntimeSurfaces.default_watch())
      |> Map.put_new(:companion, RuntimeSurfaces.default_companion())
      |> Map.put_new(:phone, RuntimeSurfaces.default_phone())
      |> update_in([:watch, :model], fn model ->
        Map.put(model, "runtime_model", %{"enabled" => true})
      end)
      |> update_in([:watch, :shell], fn shell ->
        Map.put(shell || %{}, "debugger_contract", %{
          "subscriptions_params" => ["model"],
          "init_model" => %{"enabled" => false}
        })
      end)

    guards = [%{"kind" => "field_truthy", "subject" => "model.enabled"}]

    assert SubscriptionGuards.satisfied?(state, :watch, guards)
  end
end
