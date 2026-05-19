defmodule Ide.AppStore.PublisherTest do
  use ExUnit.Case, async: false

  alias Ide.AppStore.Publisher

  test "publishes an existing app release through dashboard API" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_appstore_publisher_test_#{System.unique_integer([:positive])}"
      )

    app_root = Path.join(root, "app")
    build_root = Path.join(app_root, "build")
    File.mkdir_p!(build_root)
    on_exit(fn -> File.rm_rf(root) end)

    pbw_path = Path.join(build_root, "app.pbw")
    screenshot_path = Path.join(root, "basalt_shot_1.png")
    File.write!(pbw_path, "pbw")
    File.write!(screenshot_path, <<137, 80, 78, 71, 13, 10, 26, 10>>)

    File.write!(
      Path.join(app_root, "package.json"),
      Jason.encode!(%{
        "name" => "tangram",
        "version" => "1.0.1",
        "pebble" => %{
          "displayName" => "Tangram",
          "uuid" => "35d51bb9-42ee-4152-8f19-ba81e9db37fd",
          "targetPlatforms" => ["basalt"],
          "watchapp" => %{"watchface" => true}
        }
      })
    )

    {:ok, agent} = Agent.start_link(fn -> [] end)

    request_fun = fn method, url, headers, body, _timeout ->
      body = if is_nil(body), do: "", else: IO.iodata_to_binary(body)
      Agent.update(agent, &[{method, url, headers, body} | &1])

      cond do
        method == :get and String.ends_with?(url, "/api/v1/developer/me") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "developer" => %{"id" => "dev"},
               "app_lookup" => %{
                 "by_app_uuid" => %{"35d51bb9-42ee-4152-8f19-ba81e9db37fd" => "app-id"}
               }
             }
           }}

        method == :post and String.ends_with?(url, "/api/dashboard/apps/app-id/releases") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "message" => "ok",
               "screenshotResults" => %{"uploaded" => [%{"platform" => "basalt"}]}
             }
           }}
      end
    end

    assert {:ok, result} =
             Publisher.publish(
               %{name: "Tangram"},
               app_root: app_root,
               artifact_path: pbw_path,
               version: "1.0.1",
               release_notes: "Added screenshots",
               screenshots: [screenshot_path],
               firebase_id_token: "token",
               api_base: "https://example.test",
               request_fun: request_fun
             )

    assert result.status == :ok
    assert result.output =~ "Resolved existing appstore app ID: app-id"
    assert result.output =~ "Uploaded screenshots: 1"

    calls = Agent.get(agent, &Enum.reverse/1)
    assert [_me_call, {:post, release_url, headers, release_body}] = calls
    assert release_url == "https://example.test/api/dashboard/apps/app-id/releases"

    assert Enum.any?(headers, fn {key, value} ->
             key == "authorization" and value == "Bearer token"
           end)

    assert release_body =~ ~s(name="version")
    assert release_body =~ "1.0.1"
    assert release_body =~ ~s(name="isPublished")
    assert release_body =~ "true"
    assert release_body =~ ~s(name="replaceScreenshots")
    assert release_body =~ "true"
    assert release_body =~ ~s(name="screenshots_basalt"; filename="basalt_shot_1.png")
    assert release_body =~ ~s(name="pbwFile"; filename="app.pbw")
  end

  test "creates a new app with store icons in multipart body" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_appstore_publisher_create_test_#{System.unique_integer([:positive])}"
      )

    app_root = Path.join(root, "app")
    build_root = Path.join(app_root, "build")
    assets_root = Path.join(root, "workspace")
    File.mkdir_p!(build_root)
    File.mkdir_p!(assets_root)
    on_exit(fn -> File.rm_rf(root) end)

    pbw_path = Path.join(build_root, "app.pbw")
    icon_small = Path.join(assets_root, "store_assets/icon_small.png")
    icon_large = Path.join(assets_root, "store_assets/icon_large.png")
    File.mkdir_p!(Path.dirname(icon_small))
    File.write!(pbw_path, "pbw")
    File.write!(icon_small, png_header(80, 80))
    File.write!(icon_large, png_header(144, 144))

    File.write!(
      Path.join(app_root, "package.json"),
      Jason.encode!(%{
        "name" => "counter",
        "version" => "1.0.0",
        "pebble" => %{
          "displayName" => "Counter",
          "uuid" => "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
          "targetPlatforms" => ["basalt"],
          "watchapp" => %{"watchface" => false}
        }
      })
    )

    {:ok, agent} = Agent.start_link(fn -> [] end)

    request_fun = fn method, url, headers, body, _timeout ->
      body = if is_nil(body), do: "", else: IO.iodata_to_binary(body)
      Agent.update(agent, &[{method, url, headers, body} | &1])

      cond do
        method == :get and String.ends_with?(url, "/api/v1/developer/me") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "developer" => %{"id" => "dev"},
               "app_lookup" => %{"by_app_uuid" => %{}}
             }
           }}

        method == :post and String.ends_with?(url, "/api/dashboard/apps") ->
          {:ok, %{status: 200, body: %{"appId" => "new-app-id"}}}
      end
    end

    assert {:ok, result} =
             Publisher.publish(
               %{name: "Counter"},
               app_root: app_root,
               artifact_path: pbw_path,
               version: "1.0.0",
               description: "A simple counter watchapp.",
               release_notes: "Initial release",
               firebase_id_token: "token",
               api_base: "https://example.test",
               request_fun: request_fun,
               store_icons: %{
                 icon_small: icon_small,
                 icon_large: icon_large
               }
             )

    assert result.status == :ok
    assert result.output =~ "Creating a new app"
    assert result.output =~ "Store icons: uploaded 80×80 px (small icon) and 144×144 px (large icon)"

    calls = Agent.get(agent, &Enum.reverse/1)
    assert [_me_call, {:post, create_url, _headers, create_body}] = calls
    assert create_url == "https://example.test/api/dashboard/apps"
    assert create_body =~ ~s(name="iconSmall"; filename="icon_small.png")
    assert create_body =~ ~s(name="iconLarge"; filename="icon_large.png")
    refute create_body =~ ~s(name="iconPrompt")
  end

  test "sends iconPrompt when creating watchapp without store icons" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_appstore_publisher_prompt_test_#{System.unique_integer([:positive])}"
      )

    app_root = Path.join(root, "app")
    build_root = Path.join(app_root, "build")
    File.mkdir_p!(build_root)
    on_exit(fn -> File.rm_rf(root) end)

    pbw_path = Path.join(build_root, "app.pbw")
    File.write!(pbw_path, "pbw")

    File.write!(
      Path.join(app_root, "package.json"),
      Jason.encode!(%{
        "name" => "counter",
        "version" => "1.0.0",
        "pebble" => %{
          "displayName" => "Counter",
          "uuid" => "b2c3d4e5-f6a7-8901-bcde-f12345678901",
          "targetPlatforms" => ["basalt"],
          "watchapp" => %{"watchface" => false}
        }
      })
    )

    {:ok, agent} = Agent.start_link(fn -> [] end)

    request_fun = fn method, url, _headers, body, _timeout ->
      body = if is_nil(body), do: "", else: IO.iodata_to_binary(body)
      Agent.update(agent, &[{method, url, body} | &1])

      cond do
        method == :get and String.ends_with?(url, "/api/v1/developer/me") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "developer" => %{"id" => "dev"},
               "app_lookup" => %{"by_app_uuid" => %{}}
             }
           }}

        method == :post and String.ends_with?(url, "/api/dashboard/apps") ->
          {:ok, %{status: 200, body: %{"appId" => "new-app-id"}}}
      end
    end

    assert {:ok, result} =
             Publisher.publish(
               %{name: "Counter"},
               app_root: app_root,
               artifact_path: pbw_path,
               version: "1.0.0",
               description: "Counts things.",
               release_notes: "Initial release",
               firebase_id_token: "token",
               api_base: "https://example.test",
               request_fun: request_fun,
               store_icons: %{},
               generate_store_graphics: true,
               website: "https://elm-pebble.dev",
               source: "https://github.com/synalysis/elm-pebble"
             )

    assert result.status == :ok
    assert result.output =~ "will request Rebble AI icon generation"

    [_me, {_post, _url, create_body}] = Agent.get(agent, &Enum.reverse/1)
    assert create_body =~ ~s(name="iconPrompt")
    assert create_body =~ ~s(name="website")
    assert create_body =~ "https://elm-pebble.dev"
    assert create_body =~ ~s(name="source")
    assert create_body =~ "https://github.com/synalysis/elm-pebble"
    assert create_body =~ "Counter:"
  end

  test "skips iconPrompt when generate_store_graphics is false" do
    root =
      Path.join(
        System.tmp_dir!(),
        "ide_appstore_publisher_no_prompt_#{System.unique_integer([:positive])}"
      )

    app_root = Path.join(root, "app")
    build_root = Path.join(app_root, "build")
    File.mkdir_p!(build_root)
    on_exit(fn -> File.rm_rf(root) end)

    pbw_path = Path.join(build_root, "app.pbw")
    File.write!(pbw_path, "pbw")

    File.write!(
      Path.join(app_root, "package.json"),
      Jason.encode!(%{
        "name" => "counter",
        "version" => "1.0.0",
        "pebble" => %{
          "displayName" => "Counter",
          "uuid" => "c3d4e5f6-a7b8-9012-cdef-123456789012",
          "targetPlatforms" => ["basalt"],
          "watchapp" => %{"watchface" => false}
        }
      })
    )

    {:ok, agent} = Agent.start_link(fn -> [] end)

    request_fun = fn method, url, _headers, body, _timeout ->
      body = if is_nil(body), do: "", else: IO.iodata_to_binary(body)
      Agent.update(agent, &[{method, url, body} | &1])

      cond do
        method == :get and String.ends_with?(url, "/api/v1/developer/me") ->
          {:ok,
           %{
             status: 200,
             body: %{
               "developer" => %{"id" => "dev"},
               "app_lookup" => %{"by_app_uuid" => %{}}
             }
           }}

        method == :post and String.ends_with?(url, "/api/dashboard/apps") ->
          {:ok, %{status: 200, body: %{"appId" => "new-app-id"}}}
      end
    end

    assert {:ok, result} =
             Publisher.publish(
               %{name: "Counter"},
               app_root: app_root,
               artifact_path: pbw_path,
               version: "1.0.0",
               description: "Counts things.",
               release_notes: "Initial release",
               firebase_id_token: "token",
               api_base: "https://example.test",
               request_fun: request_fun,
               store_icons: %{},
               generate_store_graphics: false
             )

    assert result.status == :ok
    refute result.output =~ "iconPrompt"

    [_me, {_post, _url, create_body}] = Agent.get(agent, &Enum.reverse/1)
    refute create_body =~ ~s(name="iconPrompt")
  end

  defp png_header(width, height) do
    <<0x89, "PNG\r\n", 0x1A, "\n", 0::32, "IHDR", width::32, height::32, 0::32>>
  end
end
