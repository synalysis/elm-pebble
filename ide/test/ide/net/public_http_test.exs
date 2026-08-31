defmodule Ide.Net.PublicHttpTest do
  use ExUnit.Case, async: true

  alias Ide.Net.PublicHttp

  test "allows public unicast IP literals" do
    assert :ok = PublicHttp.validate_url("https://1.1.1.1/")
    assert :ok = PublicHttp.validate_url("http://8.8.8.8/path")
  end

  test "blocks loopback, private, and metadata addresses" do
    assert {:error, :blocked_url} = PublicHttp.validate_url("http://127.0.0.1/")
    assert {:error, :blocked_url} = PublicHttp.validate_url("http://localhost/secret")
    assert {:error, :blocked_url} = PublicHttp.validate_url("http://169.254.169.254/latest/meta-data/")
    assert {:error, :blocked_url} = PublicHttp.validate_url("http://10.0.0.1/")
    assert {:error, :blocked_url} = PublicHttp.validate_url("http://192.168.1.1/")
    assert {:error, :blocked_url} = PublicHttp.validate_url("http://[::1]/")
  end

  test "rejects non-http schemes, userinfo, and invalid methods" do
    assert {:error, :invalid_url} = PublicHttp.validate_url("file:///etc/passwd")
    assert {:error, :invalid_url} = PublicHttp.validate_url("not a url")
    assert {:error, :blocked_url} = PublicHttp.validate_url("https://user:pass@example.com/")
    assert {:error, :invalid_method} = PublicHttp.allowed_method("TRACE")
    assert {:ok, :get} = PublicHttp.allowed_method("GET")
  end
end
