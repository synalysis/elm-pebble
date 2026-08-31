defmodule Elmx.TeaPlaybookSamplesTest do
  use ExUnit.Case, async: true

  alias Elmx.TeaPlaybook
  alias Elmx.TeaPlaybook.Samples

  test "ProvideTide sample matches YES protocol ctor" do
    assert Samples.phone_sample_supported?("ProvideTide")
    assert Samples.phone_sample_supported?("ProvideTide", ["Int", "Int", "Int", "TideKind"])

    sample = Samples.phone_sample("ProvideTide")
    assert sample["ctor"] == "FromPhone"
    assert [%{"ctor" => "ProvideTide", "args" => args}] = sample["args"]
    assert [720, 150, 50, %{"ctor" => "HighTide", "args" => []}] = args

    assert Samples.provide_tide() == sample
  end

  test "watchface_yes playbook injects ProvideTide" do
    playbook = TeaPlaybook.for_template("watchface_yes")

    assert Enum.any?(playbook.steps, fn
             %{op: :update, action: :from_phone, ctor: "ProvideTide"} -> true
             _ -> false
           end)
  end
end
