defmodule Elmc.Runtime.ExecutorTest do
  use ExUnit.Case, async: true

  alias Elmc.Runtime.Executor

  test "execute applies deterministic message mutation contract" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"n" => 0},
        "msg_constructors" => ["Inc"],
        "update_case_branches" => ["Inc"],
        "view_case_branches" => ["Main"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"n" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Inc",
      update_branches: ["Inc"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.runtime["engine"] == "elmc_runtime_executor_v0"
    assert result.model_patch["runtime_model_source"] == "step_message"
    assert result.model_patch["runtime_model"]["n"] == 2
    assert is_map(result.view_tree)
    assert result.runtime["view_tree_source"] == "step_derived_view_tree"
    assert result.runtime["msg_constructor_count"] == 1
    assert result.runtime["update_case_branch_count"] == 1
    assert result.runtime["view_case_branch_count"] == 1
    assert is_binary(result.runtime["runtime_model_sha256"])
    assert is_binary(result.runtime["view_tree_sha256"])
    assert result.protocol_events == []
  end

  test "execute falls back to init model when no message is provided" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"n" => 3},
        "msg_constructors" => ["Inc"],
        "update_case_branches" => ["Inc", "Dec"],
        "view_case_branches" => ["Ready"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{},
      current_view_tree: %{},
      message: nil,
      update_branches: []
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model_source"] == "init_model"
    assert result.model_patch["runtime_model"]["n"] == 3
    assert result.runtime["view_tree_source"] == "parser_view_tree"
    assert result.runtime["msg_constructor_count"] == 1
    assert result.runtime["update_case_branch_count"] == 2
    assert result.runtime["view_case_branch_count"] == 1
    assert result.protocol_events == []
  end

  test "execute prefers introspected view tree on reload even when current view exists" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"n" => 3},
        "view_tree" => %{"type" => "root", "label" => "from-introspect", "children" => []}
      },
      current_model: %{},
      current_view_tree: %{"type" => "Window", "label" => "stale-current", "children" => []},
      message: nil,
      update_branches: []
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.runtime["view_tree_source"] == "parser_view_tree"
    assert result.view_tree["type"] == "root"
    assert result.view_tree["label"] == "from-introspect"
  end

  test "execute mutates only a primary numeric field per message" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0, "other" => 7},
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 3, "other" => 11}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Inc",
      update_branches: ["Inc"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 4
    assert result.model_patch["runtime_model"]["other"] == 11
  end

  test "execute reset restores selected field from init_model when available" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 2},
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 9, "other" => 4}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Reset",
      update_branches: ["Reset"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 2
    assert result.model_patch["runtime_model"]["other"] == 4
    assert result.model_patch["runtime_model"]["last_operation"] == "reset"
  end

  test "execute keeps tick operation when message does not match update branches" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"n" => 0},
        "update_case_branches" => ["Inc", "Dec"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"n" => 5, "step_counter" => 2}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:UnknownMessage",
      update_branches: ["Inc", "Dec"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["n"] == 5
    assert result.model_patch["runtime_model"]["step_counter"] == 3
    assert result.model_patch["runtime_model"]["last_operation"] == "tick"
  end

  test "execute set operation assigns primary numeric value from message payload" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0, "other" => 7},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 3, "other" => 11}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetCount:42",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
    assert result.model_patch["runtime_model"]["other"] == 11
    assert result.model_patch["runtime_model"]["last_operation"] == "set"
  end

  test "execute set operation assigns primary boolean value from message payload" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => false, "other" => 7},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => false, "other" => 11}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetEnabled:true",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == true
    assert result.model_patch["runtime_model"]["other"] == 11
    assert result.model_patch["runtime_model"]["last_operation"] == "set"
  end

  test "execute set operation assigns false boolean payload from off keyword" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => true},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true, "other" => 11}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetEnabled:off",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
    assert result.model_patch["runtime_model"]["other"] == 11
    assert result.model_patch["runtime_model"]["last_operation"] == "set"
  end

  test "execute set operation avoids boolean substring false positives" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => false},
        "update_case_branches" => ["SetLabel String"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => false, "step_counter" => 2}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetLabel:Structure",
      update_branches: ["SetLabel String"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
    assert result.model_patch["runtime_model"]["step_counter"] == 3
    assert result.model_patch["runtime_model"]["last_operation"] == "set"
  end

  test "execute ignores bookkeeping fields when selecting mutation target" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"n" => 0},
        "update_case_branches" => ["Inc"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{
        "runtime_model" => %{
          "n" => 4,
          "step_counter" => 99,
          "protocol_inbound_count" => 13
        }
      },
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Inc",
      update_branches: ["Inc"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["n"] == 5
    assert result.model_patch["runtime_model"]["step_counter"] == 99
    assert result.model_patch["runtime_model"]["protocol_inbound_count"] == 13
  end

  test "execute set integer prefers constructor payload segment over earlier numbers" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Trace99:Step:SetCount:42",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
  end

  test "execute set boolean prefers constructor payload segment over earlier flags" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => false},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Meta:true:Step:SetEnabled:false",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end

  test "execute matches qualified constructor names for set operations" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["Main.SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:Main.SetCount:42",
      update_branches: ["Main.SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
    assert result.model_patch["runtime_model"]["last_operation"] == "set"
  end

  test "execute set integer parses constructor tail for non-colon message shapes" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["Main.SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Meta9 Step Main.SetCount (Just 42)",
      update_branches: ["Main.SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
  end

  test "execute set boolean parses constructor tail for non-colon message shapes" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => false},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Meta true SetEnabled { enabled = False }",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end

  test "execute set integer prefers key-matched assignment within record-like payload" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0, "id" => 0},
        "update_case_branches" => ["SetCount Payload"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1, "id" => 7}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetCount:{ id = 3, count = 42 }",
      update_branches: ["SetCount Payload"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
    assert result.model_patch["runtime_model"]["id"] == 7
  end

  test "execute set boolean prefers key-matched assignment within record-like payload" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => false},
        "update_case_branches" => ["SetEnabled Payload"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetEnabled:{ active = true, enabled = false }",
      update_branches: ["SetEnabled Payload"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end

  test "execute set targets hinted numeric field from constructor name" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0, "total" => 0},
        "update_case_branches" => ["SetTotal Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 3, "total" => 11}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetTotal:42",
      update_branches: ["SetTotal Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 3
    assert result.model_patch["runtime_model"]["total"] == 42
  end

  test "execute set targets hinted boolean field from constructor name" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => false, "visible" => true},
        "update_case_branches" => ["SetVisible Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => false, "visible" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetVisible:false",
      update_branches: ["SetVisible Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
    assert result.model_patch["runtime_model"]["visible"] == false
  end

  test "execute set with Bool branch prefers boolean update in mixed payload" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0, "enabled" => false},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 9, "enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetEnabled:{ count = 2, enabled = false }",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
    assert result.model_patch["runtime_model"]["count"] == 9
  end

  test "execute set with Int branch prefers numeric update in mixed payload" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0, "enabled" => false},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 9, "enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetCount:{ enabled = false, count = 2 }",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 2
    assert result.model_patch["runtime_model"]["enabled"] == true
  end

  test "execute set integer prefers later constructor-tail segment over metadata segment" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Step:SetCount:(Meta 9):(Just 42)",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
  end

  test "execute set boolean uses constructor-tail payload in colon messages without step token" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => true},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Meta:true:SetEnabled (Just false)",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end

  test "execute set integer in multi-argument constructor tail prefers payload argument" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "SetCount (Flags 9) (Just 42)",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
  end

  test "execute set boolean in multi-argument constructor tail prefers payload argument" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => true},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "SetEnabled (Flags true) (Just false)",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end

  test "execute set integer prefers wrapped payload over trailing metadata tokens" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "SetCount (Just 42) meta9",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
  end

  test "execute set boolean prefers wrapped payload over trailing metadata tokens" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => true},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "SetEnabled (Just false) metaTrue",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end

  test "execute set integer prefers nested wrapped constructor tail value over competing wrappers" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Meta (Just 9) SetCount ((Just 12), [Ok 42]) trailing 7",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
  end

  test "execute set boolean prefers nested wrapped constructor tail value over competing wrappers" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => true},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Meta (Just true) SetEnabled ((Ok true), [Just false]) trailing true",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end

  test "execute set integer ignores wrapped values outside early constructor arguments" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "SetCount (Just 42) debug (Just 9)",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
  end

  test "execute set boolean ignores wrapped values outside early constructor arguments" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => true},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "SetEnabled (Just false) debug (Just true)",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end

  test "execute set integer ignores key assignment outside early constructor arguments" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "SetCount { count = 42 } debug { count = 9 }",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
  end

  test "execute set boolean ignores key assignment outside early constructor arguments" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => true},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "SetEnabled { enabled = false } debug { enabled = true }",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end

  test "execute set integer unkeyed fallback prefers constructor tail over trailing noise" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"count" => 0},
        "update_case_branches" => ["SetCount Int"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"count" => 1}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Meta9 SetCount debug payload 42 trail 7",
      update_branches: ["SetCount Int"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["count"] == 42
  end

  test "execute set boolean unkeyed fallback prefers constructor tail over metadata tokens" do
    request = %{
      source_root: "watch",
      rel_path: "watch/src/Main.elm",
      source: "module Main exposing (main)\n",
      introspect: %{
        "init_model" => %{"enabled" => true},
        "update_case_branches" => ["SetEnabled Bool"],
        "view_tree" => %{"type" => "root", "children" => []}
      },
      current_model: %{"runtime_model" => %{"enabled" => true}},
      current_view_tree: %{"type" => "root", "children" => []},
      message: "Meta:true SetEnabled debug payload false trail true",
      update_branches: ["SetEnabled Bool"]
    }

    assert {:ok, result} = Executor.execute(request)
    assert result.model_patch["runtime_model"]["enabled"] == false
  end
end
