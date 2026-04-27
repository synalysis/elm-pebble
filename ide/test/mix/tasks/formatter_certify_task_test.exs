defmodule Mix.Tasks.Formatter.CertifyTaskTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Formatter.Certify, as: CertifyTask

  test "build_parity_args includes provided options in order" do
    args =
      CertifyTask.build_parity_args(
        phase: "B",
        baseline: "tmp/base.json",
        fixtures: "/tmp/fixtures",
        shard_total: 4,
        shard_index: 2
      )

    assert args == [
             "--phase",
             "B",
             "--baseline",
             "tmp/base.json",
             "--fixtures",
             "/tmp/fixtures",
             "--shard-total",
             "4",
             "--shard-index",
             "2"
           ]
  end

  test "build_parity_args omits nil and empty values" do
    args =
      CertifyTask.build_parity_args(
        phase: "",
        baseline: nil,
        fixtures: nil,
        shard_total: nil,
        shard_index: nil
      )

    assert args == []
  end
end
