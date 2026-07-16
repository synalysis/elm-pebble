defmodule Elmc.WasmWebRouteFetchTest do
  use ExUnit.Case, async: false

  @tag :wasm_execute
  test "route bytes and navigation runtime host wiring" do
    route_bytes = Path.expand("../../elmc-wasm-runtime/host/route_bytes.js", __DIR__)
    navigation = Path.expand("../../elmc-wasm-runtime/host/navigation_runtime.js", __DIR__)
    rc_runtime = Path.expand("../../elmc-wasm-runtime/host/rc_runtime.js", __DIR__)

    assert File.regular?(route_bytes)
    route_host = File.read!(route_bytes)
    assert route_host =~ "defaultRuntimeFetcher"
    assert route_host =~ "setSiteRootFromPageHtml"

    nav = File.read!(navigation)
    refute nav =~ "[navigationKeyPtr, urlPtr]"
    assert nav =~ "invokeClosure(onUrlChangeFn, [urlPtr])"
    assert nav =~ "pendingPushUrl"
    assert nav =~ "notifyUrlChangeAfterPush"

    url_host = File.read!(Path.expand("../../elmc-wasm-runtime/host/url_runtime.js", __DIR__))
    assert url_host =~ "constructorTags"
    assert url_host =~ "urlRequestInternalTag"
    assert url_host =~ "pathFromSegments"

    assert File.regular?(rc_runtime)
    rc_host = File.read!(rc_runtime)
    assert rc_host =~ "time_zone_offset_minutes"
    assert rc_host =~ "url_from_string"
    assert rc_host =~ "deliverIncomingPortFn"
    assert rc_host =~ "string_chop_end"
    assert rc_host =~ "suffixPtr, strPtr"
    assert rc_host =~ "setRouteBytesSiteRoot"
  end
end
