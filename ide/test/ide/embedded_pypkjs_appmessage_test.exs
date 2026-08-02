defmodule Ide.EmbeddedPypkjsAppmessageTest do
  @moduledoc """
  Guards phone→watch AppMessage encoding for string wire values.

  PushLabels / PushString put cstrings on the wire; the key-shift corruption
  detector must not call `int()` on those values (Extras matrix regression).
  """
  use ExUnit.Case, async: true

  @script Path.expand("../../priv/python/embedded_pypkjs.py", __DIR__)

  setup do
    cond do
      not File.exists?(@script) ->
        {:skip, "embedded_pypkjs.py missing"}

      is_nil(pebble_python()) ->
        {:skip, "pebble-tool python with libpebble2 not available"}

      true ->
        :ok
    end
  end

  test "key-shift detector accepts PushLabels-style cstring values" do
    python = """
import importlib.util

spec = importlib.util.spec_from_file_location("embedded_pypkjs", #{inspect(@script)})
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class CString:
    def __init__(self, value):
        self.value = value
        self.type = "cstring"

class Int32:
    def __init__(self, value):
        self.value = value
        self.type = "int32"

# message_tag=209, count=2, key_0="k", val_0=10 — PushLabels shape
dictionary = {
    10: Int32(209),
    90: Int32(2),
    91: CString("k"),
    92: Int32(10),
}

mod.detect_appmessage_key_shift_corruption(dictionary)
assert mod.appmessage_log_value(dictionary[91]) == "k"
assert mod.try_appmessage_int(dictionary[91]) is None
assert mod.try_appmessage_int(dictionary[10]) == 209
print("OK")
"""

    {out, code} = System.cmd(pebble_python(), ["-c", python], stderr_to_stdout: true)
    assert code == 0, out
    assert out =~ "OK"
  end

  test "key-shift detector still rejects all-int scrambled payloads" do
    python = """
import importlib.util

spec = importlib.util.spec_from_file_location("embedded_pypkjs", #{inspect(@script)})
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class Int32:
    def __init__(self, value):
        self.value = value

# values equal next key ids — the scramble the detector exists for
dictionary = {10: Int32(20), 20: Int32(30), 30: Int32(40)}
try:
    mod.detect_appmessage_key_shift_corruption(dictionary)
except ValueError as exc:
    assert "corrupted" in str(exc)
    print("OK")
else:
    raise SystemExit("expected ValueError")
"""

    {out, code} = System.cmd(pebble_python(), ["-c", python], stderr_to_stdout: true)
    assert code == 0, out
    assert out =~ "OK"
  end

  defp pebble_python do
    candidates = [
      System.get_env("ELMC_PEBBLE_PYTHON"),
      Path.expand("~/.local/share/uv/tools/pebble-tool/bin/python"),
      Path.expand("~/.pebble-sdk/SDKs/current/.venv/bin/python")
    ]

    Enum.find(candidates, fn
      nil -> false
      path -> File.exists?(path) and python_has_libpebble2?(path)
    end)
  end

  defp python_has_libpebble2?(path) do
    case System.cmd(path, ["-c", "import libpebble2"], stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  end
end
