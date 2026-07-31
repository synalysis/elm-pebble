defmodule Ide.Debugger.HttpFlightCommitTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.HttpFlightCommit

  test "commit preserves watch updates made while http step ran outside the agent" do
    basis = %{
      debugger_seq: 1,
      seq: 1,
      debugger_timeline: [],
      events: [],
      app_message_queues: %{watch: [], companion: [], phone: []},
      watch: %{model: %{"runtime_model" => %{"companionFigure" => %{"ctor" => "Nothing"}}}},
      companion: %{model: %{"runtime_model" => %{"figure" => 0}}},
      phone: %{model: %{}}
    }

    current =
      put_in(basis.watch.model["runtime_model"]["companionFigure"], %{
        "ctor" => "Just",
        "args" => [0]
      })

    applied =
      basis
      |> put_in([:companion, :model, "runtime_model", "names"], ["page1-0"])
      |> Map.put(:debugger_seq, 2)
      |> Map.put(:pending_http_followups, [%{"followup_message" => "SvgReceived"}])
      |> Map.put(:debugger_timeline, [
        %{seq: 2, type: "update", target: "phone", message: "CatalogReceived"}
      ])

    committed = HttpFlightCommit.commit(current, applied, basis, :companion)

    assert get_in(committed, [:watch, :model, "runtime_model", "companionFigure"]) == %{
             "ctor" => "Just",
             "args" => [0]
           }

    assert get_in(committed, [:companion, :model, "runtime_model", "names"]) == ["page1-0"]
    assert [%{"followup_message" => "SvgReceived"}] = Map.get(committed, :pending_http_followups)
  end

  test "commit merges watch surface updates produced during companion http flight" do
    basis = %{
      debugger_seq: 1,
      seq: 1,
      debugger_timeline: [],
      events: [],
      app_message_queues: %{watch: [], companion: [], phone: []},
      watch: %{model: %{"runtime_model" => %{"temperature" => %{"ctor" => "Just", "args" => [%{"ctor" => "Celsius", "args" => [0]}]}}}},
      companion: %{model: %{"runtime_model" => %{"lastResponse" => 0}}},
      phone: %{model: %{}}
    }

    current = basis

    applied =
      basis
      |> put_in([:watch, :model, "runtime_model", "temperature"], %{
        "ctor" => "Just",
        "args" => [%{"ctor" => "Celsius", "args" => [21]}]
      })
      |> put_in([:companion, :model, "runtime_model", "lastResponse"], 21)
      |> Map.put(:debugger_seq, 2)

    committed = HttpFlightCommit.commit(current, applied, basis, :companion)

    assert get_in(committed, [:watch, :model, "runtime_model", "temperature"]) == %{
             "ctor" => "Just",
             "args" => [%{"ctor" => "Celsius", "args" => [21]}]
           }
    assert get_in(committed, [:companion, :model, "runtime_model", "lastResponse"]) == 21
  end

  test "commit renumbers flight timeline past concurrent watch auto-fire seqs" do
    basis = %{
      debugger_seq: 10,
      seq: 10,
      debugger_timeline: [],
      events: [],
      app_message_queues: %{watch: [], companion: [], phone: []},
      watch: %{model: %{}},
      companion: %{model: %{}},
      phone: %{model: %{}}
    }

    # Watch auto-fire advanced current while the unlocked HTTP flight still
    # numbered from basis (both would otherwise claim seq 11).
    current = %{
      basis
      | debugger_seq: 11,
        seq: 11,
        debugger_timeline: [
          %{seq: 11, type: "update", target: "watch", message: "MinuteChanged 58"}
        ]
    }

    applied = %{
      basis
      | debugger_seq: 11,
        seq: 11,
        debugger_timeline: [
          %{seq: 11, type: "update", target: "phone", message: "SvgReceived (Ok \"…\")"}
        ],
        events: [%{seq: 11, type: "update", target: "phone"}]
    }

    committed = HttpFlightCommit.commit(current, applied, basis, :phone)

    assert committed.debugger_seq == 12
    assert committed.seq == 12

    assert [
             %{seq: 12, target: "phone", message: "SvgReceived (Ok \"…\")"},
             %{seq: 11, target: "watch", message: "MinuteChanged 58"}
           ] = committed.debugger_timeline

    refute Enum.any?(committed.debugger_timeline, fn row ->
             Enum.count(committed.debugger_timeline, &(&1.seq == row.seq)) > 1
           end)
  end

  test "commit appends protocol deliveries instead of replacing in-flight queue" do
    basis = %{
      debugger_seq: 1,
      seq: 1,
      debugger_timeline: [],
      events: [],
      pending_protocol_deliveries: [],
      watch: %{model: %{}},
      companion: %{model: %{}},
      phone: %{model: %{}}
    }

    current = %{
      basis
      | pending_protocol_deliveries: [
          %{"recipient" => "watch", "payload" => %{"message" => "BeginFigure 0"}}
        ]
    }

    applied = %{
      basis
      | pending_protocol_deliveries: [
          %{"recipient" => "watch", "payload" => %{"message" => "ProvidePiece 0"}}
        ]
    }

    committed = HttpFlightCommit.commit(current, applied, basis, :companion)

    assert [
             %{"recipient" => "watch", "payload" => %{"message" => "BeginFigure 0"}},
             %{"recipient" => "watch", "payload" => %{"message" => "ProvidePiece 0"}}
           ] = Map.get(committed, :pending_protocol_deliveries)
  end
end
