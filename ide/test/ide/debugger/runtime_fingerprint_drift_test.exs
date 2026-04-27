defmodule Ide.Debugger.RuntimeFingerprintDriftTest do
  use ExUnit.Case, async: true

  alias Ide.Debugger.RuntimeFingerprintDrift

  test "backend_drift_detail formats compare-style backend rows" do
    compare = %{
      surfaces: %{
        watch: %{
          backend_changed: true,
          current_execution_backend: "external",
          compare_execution_backend: "default",
          current_external_fallback_reason: "{:external_failed, :boom}",
          compare_external_fallback_reason: nil
        },
        companion: %{
          backend_changed: false,
          current_execution_backend: "default",
          compare_execution_backend: "default"
        }
      }
    }

    detail = RuntimeFingerprintDrift.backend_drift_detail(compare)
    assert is_binary(detail)
    assert detail =~ "watch=external->default"
    assert detail =~ "[reason"
    refute detail =~ "companion="
  end

  test "backend_drift_detail supports baseline-style backend keys" do
    compare = %{
      surfaces: %{
        watch: %{
          "backend_changed" => true,
          "current_execution_backend" => "external",
          "baseline_execution_backend" => "default",
          "current_external_fallback_reason" => "current_reason",
          "baseline_external_fallback_reason" => "baseline_reason"
        }
      }
    }

    detail =
      RuntimeFingerprintDrift.backend_drift_detail(compare,
        compare_backend_keys: [:baseline_execution_backend],
        compare_reason_keys: [:baseline_external_fallback_reason]
      )

    assert detail == "watch=external->default [reason current_reason -> baseline_reason]"
  end

  test "key_target_drift_detail formats compare-style key target rows" do
    compare = %{
      surfaces: %{
        watch: %{
          key_target_changed: true,
          current_active_target_key: "count",
          compare_active_target_key: "total",
          current_active_target_key_source: "var_hint",
          compare_active_target_key_source: "primary_fallback"
        }
      }
    }

    detail = RuntimeFingerprintDrift.key_target_drift_detail(compare)
    assert detail == "watch=count(var_hint)->total(primary_fallback)"
  end

  test "key_target_drift_detail supports baseline-style key target keys" do
    compare = %{
      surfaces: %{
        watch: %{
          "key_target_changed" => true,
          "current_active_target_key" => "visible",
          "baseline_active_target_key" => "enabled",
          "current_active_target_key_source" => "field_hint",
          "baseline_active_target_key_source" => "primary_fallback"
        }
      }
    }

    detail =
      RuntimeFingerprintDrift.key_target_drift_detail(compare,
        compare_key_keys: [:baseline_active_target_key],
        compare_source_keys: [:baseline_active_target_key_source]
      )

    assert detail == "watch=visible(field_hint)->enabled(primary_fallback)"
  end

  test "merge_drift_detail combines backend and key-target snippets" do
    assert RuntimeFingerprintDrift.merge_drift_detail(
             "watch=external->default",
             "watch=count(var)->total(primary)"
           ) ==
             "backend: watch=external->default | key-target: watch=count(var)->total(primary)"

    assert RuntimeFingerprintDrift.merge_drift_detail("watch=external->default", nil) ==
             "backend: watch=external->default"

    assert RuntimeFingerprintDrift.merge_drift_detail(nil, "watch=count(var)->total(primary)") ==
             "key-target: watch=count(var)->total(primary)"

    assert RuntimeFingerprintDrift.merge_drift_detail(nil, nil) == nil
  end

  test "detail formatting is deterministic across surface map insertion order" do
    row_watch = %{
      backend_changed: true,
      current_execution_backend: "external",
      compare_execution_backend: "default"
    }

    row_phone = %{
      backend_changed: true,
      current_execution_backend: "default",
      compare_execution_backend: "external"
    }

    compare_a = %{surfaces: Enum.into([watch: row_watch, phone: row_phone], %{})}
    compare_b = %{surfaces: Enum.into([phone: row_phone, watch: row_watch], %{})}

    detail_a = RuntimeFingerprintDrift.backend_drift_detail(compare_a)
    detail_b = RuntimeFingerprintDrift.backend_drift_detail(compare_b)

    assert detail_a == detail_b
    assert detail_a == "phone=default->external, watch=external->default"
  end

  test "key_target_drift_detail truncates long key/source values with max_len" do
    compare = %{
      surfaces: %{
        watch: %{
          key_target_changed: true,
          current_active_target_key: "very_long_current_target_name",
          compare_active_target_key: "very_long_compare_target_name",
          current_active_target_key_source: "very_long_current_source_name",
          compare_active_target_key_source: "very_long_compare_source_name"
        }
      }
    }

    detail = RuntimeFingerprintDrift.key_target_drift_detail(compare, max_len: 12)
    assert is_binary(detail)
    assert detail =~ "watch=very_long...(very_long...)->very_long...(very_long...)"
  end

  test "merged drift detail keeps backend then key-target ordering for same compare" do
    compare = %{
      surfaces: %{
        watch: %{
          backend_changed: true,
          key_target_changed: true,
          current_execution_backend: "external",
          compare_execution_backend: "default",
          current_external_fallback_reason: "boom",
          compare_external_fallback_reason: "ok",
          current_active_target_key: "count",
          compare_active_target_key: "total",
          current_active_target_key_source: "var_hint",
          compare_active_target_key_source: "primary_fallback"
        }
      }
    }

    backend = RuntimeFingerprintDrift.backend_drift_detail(compare)
    key_target = RuntimeFingerprintDrift.key_target_drift_detail(compare)
    merged = RuntimeFingerprintDrift.merge_drift_detail(backend, key_target)

    assert backend == "watch=external->default [reason boom -> ok]"
    assert key_target == "watch=count(var_hint)->total(primary_fallback)"

    assert merged ==
             "backend: watch=external->default [reason boom -> ok] | key-target: watch=count(var_hint)->total(primary_fallback)"
  end

  test "detail formatting handles mixed atom and string keys in same surfaces map" do
    compare = %{
      surfaces: %{
        "watch" => %{
          "backend_changed" => true,
          "key_target_changed" => true,
          "current_execution_backend" => "external",
          "compare_execution_backend" => "default",
          "current_active_target_key" => "count",
          "compare_active_target_key" => "total",
          "current_active_target_key_source" => "var_hint",
          "compare_active_target_key_source" => "primary_fallback"
        },
        companion: %{
          backend_changed: true,
          key_target_changed: true,
          current_execution_backend: "default",
          compare_execution_backend: "external",
          current_active_target_key: "enabled",
          compare_active_target_key: "visible",
          current_active_target_key_source: "field_hint",
          compare_active_target_key_source: "primary_fallback"
        }
      }
    }

    backend = RuntimeFingerprintDrift.backend_drift_detail(compare)
    key_target = RuntimeFingerprintDrift.key_target_drift_detail(compare)
    merged = RuntimeFingerprintDrift.merge_drift_detail(backend, key_target)

    assert backend == "companion=default->external, watch=external->default"

    assert key_target ==
             "companion=enabled(field_hint)->visible(primary_fallback), watch=count(var_hint)->total(primary_fallback)"

    assert merged ==
             "backend: companion=default->external, watch=external->default | key-target: companion=enabled(field_hint)->visible(primary_fallback), watch=count(var_hint)->total(primary_fallback)"
  end

  test "backend/key-target detail reads nested current/compare rows without unknown leakage" do
    compare = %{
      surfaces: %{
        watch: %{
          backend_changed: true,
          key_target_changed: true,
          current: %{
            execution_backend: "external",
            external_fallback_reason: "boom",
            active_target_key: "count",
            active_target_key_source: "var_hint"
          },
          compare: %{
            execution_backend: "default",
            external_fallback_reason: "ok",
            active_target_key: "total",
            active_target_key_source: "primary_fallback"
          }
        }
      }
    }

    backend = RuntimeFingerprintDrift.backend_drift_detail(compare)
    key_target = RuntimeFingerprintDrift.key_target_drift_detail(compare)

    assert backend == "watch=external->default [reason boom -> ok]"
    assert key_target == "watch=count(var_hint)->total(primary_fallback)"
  end

  test "detail formatting handles partial rows with placeholders only where needed" do
    compare = %{
      surfaces: %{
        watch: %{
          backend_changed: true,
          current_execution_backend: "external"
        }
      }
    }

    backend = RuntimeFingerprintDrift.backend_drift_detail(compare)
    assert backend == "watch=external->unknown"

    key_target = RuntimeFingerprintDrift.key_target_drift_detail(compare)
    assert key_target == nil
  end

  test "key-target detail preserves explicit false values instead of treating them as missing" do
    compare = %{
      surfaces: %{
        watch: %{
          key_target_changed: true,
          current: %{
            active_target_key: false,
            active_target_key_source: "field_hint"
          },
          compare: %{
            active_target_key: true,
            active_target_key_source: "primary_fallback"
          }
        }
      }
    }

    detail = RuntimeFingerprintDrift.key_target_drift_detail(compare)
    assert detail == "watch=false(field_hint)->true(primary_fallback)"
  end

  test "backend detail reads nested baseline map when compare map is absent" do
    compare = %{
      surfaces: %{
        watch: %{
          backend_changed: true,
          current_execution_backend: "external",
          baseline: %{
            execution_backend: "default",
            external_fallback_reason: "fallback_reason"
          }
        }
      }
    }

    detail =
      RuntimeFingerprintDrift.backend_drift_detail(compare,
        compare_backend_keys: [:baseline_execution_backend],
        compare_reason_keys: [:baseline_external_fallback_reason]
      )

    assert detail == "watch=external->default [baseline reason fallback_reason]"
  end
end
