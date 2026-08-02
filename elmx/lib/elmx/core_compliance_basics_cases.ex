defmodule Elmx.CoreComplianceBasicsCases do
  @moduledoc """
  Expected Int oracles for `CoreCompliance` Basics helpers.

  Shared by elmx runtime tests and elmc↔elmx differential. Values must match
  Elm 0.19 `elm/core` Basics semantics (especially `degrees`/`radians`).
  """

  @type case_t :: {atom(), list(), integer()}

  @cases [
    {:basicsDegreesPiTrunc, [0], 0},
    {:basicsDegrees180Milli, [0], 3141},
    {:basicsRadians180Trunc, [0], 180},
    {:basicsRadiansPiMilli, [0], 3141},
    {:basicsTurns1Trunc, [0], 6},
    {:basicsSin0Round, [0], 0},
    {:basicsCos0Round, [0], 1},
    {:basicsSin90Milli, [0], 1000},
    {:basicsAsin0Trunc, [0], 0},
    {:basicsAcos1Trunc, [0], 0},
    {:basicsAtan2QuarterTrunc, [0], 0},
    {:basicsSqrt16, [0], 4},
    {:basicsLogBase2Of8, [0], 3},
    {:basicsPiMilli, [0], 3141},
    {:basicsEMilli, [0], 2718},
    {:basicsRound, [0], 4},
    {:basicsFloor, [0], 3},
    {:basicsCeiling, [0], 4},
    {:basicsTruncate, [0], 3},
    {:basicsToFloatTrunc, [0], 9},
    {:basicsAbs, [0], 6},
    {:basicsNegate, [0], 4},
    {:basicsNot, [0], 1},
    {:basicsXor, [0], 1},
    {:basicsRemainderBy, [0], 1},
    {:basicsIdentity, [0], 42},
    {:basicsAlways, [0], 99},
    {:basicsCompareOrder, [0], 111},
    {:basicsIsNan, [0], 1},
    {:basicsIsInfinite, [0], 1},
    {:basicsFromPolar5, [0], 5},
    {:basicsToPolarRadius, [0], 5}
  ]

  @spec cases() :: [case_t()]
  def cases, do: @cases

  @spec names() :: [atom()]
  def names, do: Enum.map(@cases, &elem(&1, 0))
end
