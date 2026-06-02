defmodule Ide.Resources.GifToApngTest do
  use ExUnit.Case, async: true

  alias Ide.Resources.{ApngProbe, GifToApng}

  @tag :gif2apng
  test "convert handles absolute upload paths (gif2apng requires relative cwd)" do
    case GifToApng.gif2apng_bin() do
      nil ->
        :ok

      _bin ->
        src =
          Path.join(System.tmp_dir!(), "gif2apng_abs_in_#{System.unique_integer([:positive])}")

        File.mkdir_p!(src)
        gif = Path.join(src, "sprite.gif")

        fixture = Path.join(__DIR__, "../../fixtures/animations/simple.gif")
        File.cp!(fixture, gif)

        out =
          Path.join(
            System.tmp_dir!(),
            "gif2apng_abs_out_#{System.unique_integer([:positive])}.png"
          )

        assert :ok = GifToApng.convert(gif, out)
        assert File.exists?(out)
        assert {:ok, %{frame_count: frames}} = ApngProbe.probe(out)
        assert frames > 1
    end
  end

  test "gif2apng_bin uses GIF2APNG_BIN when set" do
    path = Path.join(System.tmp_dir!(), "gif2apng_env_#{System.unique_integer([:positive])}")
    File.write!(path, "")

    prev = System.get_env("GIF2APNG_BIN")

    on_exit(fn ->
      restore_env("GIF2APNG_BIN", prev)
      File.rm(path)
    end)

    System.put_env("GIF2APNG_BIN", path)
    assert GifToApng.gif2apng_bin() == path
  end

  defp restore_env(key, value) do
    if value do
      System.put_env(key, value)
    else
      System.delete_env(key)
    end
  end
end
