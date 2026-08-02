defmodule Elmx.BasicsDegreesRadiansTest do
  use ExUnit.Case, async: true

  alias Elmx.Runtime.Core.Math

  test "Basics.degrees converts degrees to radians (Elm semantics)" do
    assert_in_delta Math.degrees(180), :math.pi(), 1.0e-9
    assert_in_delta Math.degrees(90), :math.pi() / 2.0, 1.0e-9
    assert_in_delta Math.degrees(0), 0.0, 1.0e-12
  end

  test "Basics.radians is identity on radian values" do
    assert_in_delta Math.radians(:math.pi()), :math.pi(), 1.0e-12
    assert_in_delta Math.radians(180.0), 180.0, 1.0e-12
  end

  test "degrees/radians match elmc runtime (deg→rad, rad identity)" do
    # elmc: degrees(x) = x * pi/180; radians(x) = x
    refute_in_delta Math.degrees(:math.pi()), 180.0, 1.0
    assert_in_delta Math.degrees(:math.pi()), :math.pi() * :math.pi() / 180.0, 1.0e-9
  end
end
