defmodule Elmc.BytecodeListCaseOpsTest do
  use ExUnit.Case, async: true

  alias Elmc.Backend.Bytecode.{Lower, Opcodes, Runtime}
  alias Elmc.Backend.Plan.Types.{Block, FunctionPlan, Param}

  test "test_list_empty and int list peel run in bytecode VM" do
    plan = %FunctionPlan{
      module: "Main",
      name: "probe",
      params: [%Param{name: "cells", type: nil, index: 0}],
      return_type: nil,
      fallible: false,
      rc_required: false,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %{op: :load_param, dest: 0, args: %{index: 0}, effects: %{}},
            %{op: :test_list_empty, dest: 1, args: %{reg: 0}, effects: %{}}
          ],
          terminator: {:br_if, 1, 2, 1}
        },
        %Block{
          id: 1,
          instrs: [
            %{op: :const_int, dest: 2, args: %{value: 0}, effects: %{}}
          ],
          terminator: {:ret, 2}
        },
        %Block{
          id: 2,
          instrs: [
            %{
              op: :call_runtime,
              dest: 3,
              args: %{builtin: :int_list_head_int, args: [0]},
              effects: %{}
            },
            %{
              op: :call_runtime,
              dest: 4,
              args: %{builtin: :int_list_tail, args: [0]},
              effects: %{}
            },
            %{op: :test_list_empty, dest: 5, args: %{reg: 4}, effects: %{}}
          ],
          terminator: {:ret, 5}
        }
      ],
      entry_block: 0,
      locals: %{},
      reg_count: 6,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: nil,
      fusion_data: nil
    }

    section = Lower.lower(plan)

    assert {:ok, 0} = Runtime.run_section(section, params: [[]])
    assert {:ok, 0} = Runtime.run_section(section, params: [[1, 2, 3]])
    assert {:ok, 1} = Runtime.run_section(section, params: [[1]])
  end

  test "registered opcodes include list case test ops" do
    assert Opcodes.opcode(:test_list_empty) == 33
    assert Opcodes.opcode(:test_ctor_tag) == 34
    assert Opcodes.opcode(:test_bool) == 35
    assert Opcodes.opcode(:bool_and) == 36
  end

  test "bool_and combines native bool registers" do
    plan = %FunctionPlan{
      module: "Main",
      name: "probe",
      params: [],
      return_type: nil,
      fallible: false,
      rc_required: false,
      blocks: [
        %Block{
          id: 0,
          instrs: [
            %{op: :const_int, dest: 0, args: %{value: 1}, effects: %{}},
            %{op: :const_int, dest: 1, args: %{value: 0}, effects: %{}},
            %{op: :bool_and, dest: 2, args: %{left: 0, right: 1}, effects: %{}},
            %{op: :bool_and, dest: 3, args: %{left: 0, right: 0}, effects: %{}}
          ],
          terminator: {:ret, 3}
        }
      ],
      entry_block: 0,
      locals: %{},
      reg_count: 4,
      catch_depth: 0,
      lambdas: [],
      lambda_arg_count: nil,
      letrec_refs: [],
      fusion_c: nil,
      fusion_kind: nil,
      fusion_data: nil
    }

    section = Lower.lower(plan)
    assert {:ok, 1} = Runtime.run_section(section, params: [])
  end
end
