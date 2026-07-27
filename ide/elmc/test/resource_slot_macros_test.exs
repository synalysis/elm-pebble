defmodule Elmc.ResourceSlotMacrosTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.CCodegen.CaseCompile
  alias Elmc.Backend.CCodegen.ConstructorTagCase
  alias Elmc.Backend.CCodegen.IntLiteralRef
  alias Elmc.Backend.CCodegen.ResourceSlotMacros
  alias ElmEx.IR

  setup do
    Elmc.Backend.CCodegen.ValueSlots.reset()

    Process.put(:elmc_vector_resource_slots, %{
      "VectorAnimatedTransitionClearToCloudy" => 10,
      "VectorStaticWeatherClear" => 1
    })

    on_exit(fn -> Process.delete(:elmc_vector_resource_slots) end)
    :ok
  end

  test "literal_ref names pebble resource slots" do
    expr = %{
      op: :int_literal,
      value: 1,
      union_ctor: "Pebble.Ui.Resources.VectorAnimatedTransitionClearToCloudy"
    }

    assert ResourceSlotMacros.literal_ref(expr) ==
             "ELMC_RESOURCE_SLOT_VECTORANIMATEDTRANSITIONCLEARTOCLOUDY"

    assert IntLiteralRef.ref(expr, %{}) ==
             "ELMC_RESOURCE_SLOT_VECTORANIMATEDTRANSITIONCLEARTOCLOUDY"
  end

  test "define_lines emits slot macros from Resources unions" do
    ir = %IR{
      modules: [
        %IR.Module{
          name: "Pebble.Ui.Resources",
          imports: [],
          declarations: [],
          unions: %{
            "AnimatedVector" => %{
              tags: %{
                "VectorAnimatedTransitionClearToCloudy" => 1,
                "NoAnimatedVector" => 0
              }
            },
            "StaticVector" => %{
              tags: %{
                "VectorStaticWeatherClear" => 1,
                "NoStaticVector" => 0
              }
            }
          },
          ports: [],
          port_module: false
        }
      ],
      diagnostics: []
    }

    lines = ResourceSlotMacros.define_lines(ir)

    assert {"ELMC_RESOURCE_SLOT_VECTORANIMATEDTRANSITIONCLEARTOCLOUDY", 2} in lines
    assert {"ELMC_RESOURCE_SLOT_VECTORSTATICWEATHERCLEAR", 1} in lines
    refute Enum.any?(lines, fn {name, _} -> String.contains?(name, "NOANIMATED") end)
  end

  test "case branch int literals use resource slot macros" do
    expr = %{
      op: :int_literal,
      value: 1,
      union_ctor: "Pebble.Ui.Resources.VectorAnimatedTransitionClearToCloudy"
    }

    {_prefix, assignment, _counter} =
      CaseCompile.branch_assignment(expr, "tmp_1", %{__rc_catch__: true}, 0)

    assert assignment =~ "ELMC_RESOURCE_SLOT_VECTORANIMATEDTRANSITIONCLEARTOCLOUDY"
    refute assignment =~ "elmc_new_int(&tmp_1, 10)"
  end

  test "constructor tag switch boxes one int after branch slot selection" do
    slot_expr = fn ctor ->
      %{
        op: :int_literal,
        value: 1,
        union_ctor: "Pebble.Ui.Resources." <> ctor
      }
    end

    branches = [
      %{
        pattern: %{kind: :constructor, tag: 1, name: "VectorStaticWeatherClear", arg_pattern: nil},
        expr: slot_expr.("VectorStaticWeatherClear")
      },
      %{
        pattern: %{kind: :constructor, tag: 2, name: "VectorStaticWeatherCloudy", arg_pattern: nil},
        expr: slot_expr.("VectorStaticWeatherCloudy")
      },
      %{
        pattern: %{kind: :constructor, tag: 3, name: "VectorStaticWeatherFog", arg_pattern: nil},
        expr: %{
          op: :int_literal,
          value: 2,
          union_ctor: "Pebble.Ui.Resources.VectorAnimatedTransitionClearToCloudy"
        }
      },
      %{
        pattern: %{kind: :constructor, tag: 4, name: "VectorStaticWeatherRain", arg_pattern: nil},
        expr: slot_expr.("VectorStaticWeatherClear")
      },
      %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
    ]

    Process.put(:elmc_vector_resource_slots, %{
      "VectorStaticWeatherClear" => 1,
      "VectorStaticWeatherCloudy" => 2,
      "VectorStaticWeatherFog" => 3,
      "VectorStaticWeatherRain" => 4,
      "VectorAnimatedTransitionClearToCloudy" => 10
    })

    env = %{
      "weather" => "weather_var",
      __rc_catch__: true,
      __rc_required__: true
    }

    {code, out, _counter} =
      ConstructorTagCase.compile_boxed_subject("weather", branches, env, 0)

    assert out == "owned[0]"
    assert code =~ "case_int_2"
    refute code =~ "case_box_"
    assert code =~ "case_int_2 = -1"
    assert code =~ "if (case_int_2 >= 0)"
    assert code =~ "ELMC_RESOURCE_SLOT_VECTORSTATICWEATHERCLEAR"
    assert code =~ "ELMC_RESOURCE_SLOT_VECTORANIMATEDTRANSITIONCLEARTOCLOUDY"
    assert Regex.scan(~r/elmc_new_int\(&#{Regex.escape(out)},/, code) |> length() == 1
    refute code =~ "case ELMC_UNION"
    assert code =~ "default:"
    assert code =~ "case_int_2 = 0"
    refute code =~ "elmc_int_zero()"
  end

  test "exhaustive constructor tag switch omits default and boxes int once" do
    slot_expr = fn ctor ->
      %{
        op: :int_literal,
        value: 1,
        union_ctor: "Pebble.Ui.Resources." <> ctor
      }
    end

    branches = [
      %{
        pattern: %{kind: :constructor, tag: 1, name: "VectorStaticWeatherClear", arg_pattern: nil},
        expr: slot_expr.("VectorStaticWeatherClear")
      },
      %{
        pattern: %{kind: :constructor, tag: 2, name: "VectorStaticWeatherCloudy", arg_pattern: nil},
        expr: slot_expr.("VectorStaticWeatherCloudy")
      },
      %{
        pattern: %{kind: :constructor, tag: 3, name: "VectorStaticWeatherFog", arg_pattern: nil},
        expr: slot_expr.("VectorStaticWeatherFog")
      },
      %{
        pattern: %{kind: :constructor, tag: 4, name: "VectorStaticWeatherRain", arg_pattern: nil},
        expr: slot_expr.("VectorStaticWeatherRain")
      }
    ]

    Process.put(:elmc_vector_resource_slots, %{
      "VectorStaticWeatherClear" => 1,
      "VectorStaticWeatherCloudy" => 2,
      "VectorStaticWeatherFog" => 3,
      "VectorStaticWeatherRain" => 4
    })

    env = %{
      "weather" => "weather_var",
      __rc_catch__: true,
      __rc_required__: true
    }

    {code, out, _counter} =
      ConstructorTagCase.compile_boxed_subject("weather", branches, env, 0)

    assert out == "owned[0]"
    refute code =~ "default:"
    refute code =~ "case_box_"
    refute code =~ "if (case_int_2"
    refute code =~ ~r/elmc_int_t case_int_2 =/
    assert code =~ "Rc = elmc_new_int(&#{out}, case_int_2);"
  end

  test "exhaustive constructor tag switch assigns zero literal to int scratch" do
    branches = [
      %{
        pattern: %{kind: :constructor, tag: 0, name: "StepCount", arg_pattern: nil},
        expr: %{op: :int_literal, value: 0}
      },
      %{
        pattern: %{kind: :constructor, tag: 1, name: "ActiveMinutes", arg_pattern: nil},
        expr: %{op: :int_literal, value: 1}
      },
      %{
        pattern: %{kind: :constructor, tag: 2, name: "DistanceMeters", arg_pattern: nil},
        expr: %{op: :int_literal, value: 2}
      },
      %{
        pattern: %{kind: :constructor, tag: 3, name: "SleepSeconds", arg_pattern: nil},
        expr: %{op: :int_literal, value: 3}
      }
    ]

    env = %{
      "metric" => "metric_var",
      __rc_catch__: true,
      __rc_required__: true
    }

    {code, out, _counter} =
      ConstructorTagCase.compile_boxed_subject("metric", branches, env, 0)

    assert out == "owned[0]"
    refute code =~ ~r/elmc_int_t case_int_2 =/
    refute code =~ "elmc_int_zero()"
    assert code =~ "case_int_2 = 0"
    assert code =~ "case_int_2 = 1"
    assert code =~ "Rc = elmc_new_int(&#{out}, case_int_2);"
  end

  test "constructor tag switch boxes one string after branch literal selection" do
    branches = [
      %{
        pattern: %{kind: :constructor, tag: 1, name: "Clear", arg_pattern: nil},
        expr: %{op: :string_literal, value: "Clear"}
      },
      %{
        pattern: %{kind: :constructor, tag: 2, name: "Cloudy", arg_pattern: nil},
        expr: %{op: :string_literal, value: "Cloudy"}
      },
      %{
        pattern: %{kind: :constructor, tag: 3, name: "Fog", arg_pattern: nil},
        expr: %{op: :string_literal, value: "Fog"}
      },
      %{
        pattern: %{kind: :constructor, tag: 4, name: "Rain", arg_pattern: nil},
        expr: %{op: :string_literal, value: "Rain"}
      },
      %{pattern: %{kind: :wildcard}, expr: %{op: :int_literal, value: 0}}
    ]

    env = %{
      "weather" => "weather_var",
      __rc_catch__: true,
      __rc_required__: true
    }

    {code, out, _counter} =
      ConstructorTagCase.compile_boxed_subject("weather", branches, env, 0)

    assert out == "owned[0]"
    refute code =~ "case_box_"
    assert code =~ "native_str_immortal_"
    assert code =~ "(void *)\"Clear\""
    assert code =~ "(void *)\"Rain\""
    assert Regex.scan(~r/\*&#{Regex.escape(out)} = /, code) |> length() == 4
    refute code =~ "elmc_new_string("
    assert code =~ "default:"
    assert code =~ "elmc_int_zero()"
  end

  test "exhaustive constructor tag switch omits default and boxes string once" do
    branches = [
      %{
        pattern: %{kind: :constructor, tag: 1, name: "Clear", arg_pattern: nil},
        expr: %{op: :string_literal, value: "Clear"}
      },
      %{
        pattern: %{kind: :constructor, tag: 2, name: "Cloudy", arg_pattern: nil},
        expr: %{op: :string_literal, value: "Cloudy"}
      },
      %{
        pattern: %{kind: :constructor, tag: 3, name: "Fog", arg_pattern: nil},
        expr: %{op: :string_literal, value: "Fog"}
      },
      %{
        pattern: %{kind: :constructor, tag: 4, name: "Rain", arg_pattern: nil},
        expr: %{op: :string_literal, value: "Rain"}
      }
    ]

    env = %{
      "weather" => "weather_var",
      __rc_catch__: true,
      __rc_required__: true
    }

    {code, out, _counter} =
      ConstructorTagCase.compile_boxed_subject("weather", branches, env, 0)

    assert out == "owned[0]"
    refute code =~ "default:"
    refute code =~ "case_box_"
    refute code =~ "if (case_str_2)"
    assert Regex.scan(~r/\*&#{Regex.escape(out)} = /, code) |> length() == 4
    refute code =~ "elmc_new_string("
  end
end
