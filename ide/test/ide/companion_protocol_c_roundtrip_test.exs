defmodule Ide.CompanionProtocolCRoundtripTest do
  use ExUnit.Case, async: false

  alias Ide.CompanionProtocolCTestHarness

  @protocol_matrix_types Path.join([
                           "priv",
                           "project_templates",
                           "companion_demo_protocol_matrix",
                           "protocol",
                           "src",
                           "Companion",
                           "Types.elm"
                         ])

  @tutorial_types """
  module Companion.Types exposing (Location(..), PhoneToWatch(..), Temperature(..), TutorialColor(..), WatchToPhone(..))

  type Location
      = CurrentLocation
      | Berlin
      | Zurich

  type Temperature
      = Celsius Int
      | Fahrenheit Int

  type TutorialColor
      = Black
      | White

  type WatchToPhone
      = RequestWeather Location
      | RequestUpdate

  type PhoneToWatch
      = ProvideTemperature Temperature
      | SetBackgroundColor TutorialColor
      | SetShowDate Bool
      | SetLabel String
  """

  setup do
    if is_nil(System.find_executable("cc")) do
      {:skip, "cc not available"}
    else
      :ok
    end
  end

  test "protocol matrix generated C round-trips watch encode and phone decode for every constructor" do
    types = Path.expand(@protocol_matrix_types, Path.join(__DIR__, "../.."))
    assert File.exists?(types)
    assert :ok = CompanionProtocolCTestHarness.run_roundtrip!(types)
  end

  test "tutorial weather generated C round-trips watch encode and phone decode for every constructor" do
    tmp = Path.join(System.tmp_dir!(), "companion-c-rt-tutorial-#{System.unique_integer([:positive])}")
    types = Path.join(tmp, "Types.elm")

    try do
      File.mkdir_p!(tmp)
      File.write!(types, @tutorial_types)
      assert :ok = CompanionProtocolCTestHarness.run_roundtrip!(types)
    after
      File.rm_rf(tmp)
    end
  end
end
