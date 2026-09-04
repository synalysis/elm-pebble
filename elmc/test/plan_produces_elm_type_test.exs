defmodule Elmc.PlanProducesElmTypeTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Plan.Types
  alias ElmEx.Typesys.Type

  test "produces_from_elm_type derives native tags from Type.t()" do
    assert Types.produces_from_elm_type(Type.int(), 3) == {:native_int, 3}
    assert Types.produces_from_elm_type(Type.bool(), 4) == {:native_bool, 4}
    assert Types.produces_from_elm_type(Type.list(Type.int()), 5) == {:owned, 5}
    assert Types.produces_from_elm_type(Type.string(), 6) == {:owned, 6}
  end
end
