defmodule IdeWeb.TokenizerControllerTest do
  use IdeWeb.ConnCase, async: false

  setup do
    original_auth = Application.get_env(:ide, Ide.Auth, [])
    Application.put_env(:ide, Ide.Auth, Keyword.put(original_auth, :mode, :local))

    on_exit(fn ->
      Application.put_env(:ide, Ide.Auth, original_auth)
    end)

    :ok
  end

  test "POST /api/tokenize returns token payload", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/tokenize", Jason.encode!(%{source: "module Main exposing (main)"}))

    body = json_response(conn, 200)
    assert is_list(body["tokens"])
    assert is_list(body["diagnostics"])
  end

  test "POST /api/tokenize rejects missing source", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/tokenize", Jason.encode!(%{}))

    assert json_response(conn, 400)["error"] =~ "source"
  end

  test "POST /api/tokenize includes Elm-style parser diagnostics metadata", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> post(~p"/api/tokenize", Jason.encode!(%{source: "{- comment"}))

    body = json_response(conn, 200)
    [diagnostic | _] = body["diagnostics"]

    assert diagnostic["source"] == "tokenizer"
    assert diagnostic["catalog_id"] == "endless_comment"
    assert diagnostic["catalog_version"] == "elm-compiler-0.19.1-syntax-full-v1"
    assert is_binary(diagnostic["elm_title"])
    assert is_binary(diagnostic["elm_hint"])
  end
end
