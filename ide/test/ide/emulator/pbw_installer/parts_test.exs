defmodule Ide.Emulator.PBWInstaller.PartsTest do
  use ExUnit.Case, async: true

  alias Ide.Emulator.PBWInstaller.Parts

  defp part(kind), do: %{kind: kind, object_type: :app, name: "#{kind}", size: 1, data: <<>>}

  test "sort_parts_for_install/1 orders binary, resources, worker, then other kinds" do
    parts = [part(:worker), part(:other), part(:resources), part(:binary)]

    assert Enum.map(Parts.sort_parts_for_install(parts), & &1.kind) == [
             :binary,
             :resources,
             :worker,
             :other
           ]
  end
end
