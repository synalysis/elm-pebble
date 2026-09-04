defmodule ElmEx.Typesys.Kernel.Web do
  @moduledoc """
  elm/html, elm/browser, elm/http, elm/file, elm/svg, elm/bytes, elm/url,
  and elm-pages BackendTask schemes used by wasm fixtures.

  These packages are not typechecked from source; language constructs still
  use the official arities (`Html msg`, `Program flags model msg`, …).
  """

  alias ElmEx.Typesys.{Env, Parser, Type}

  @element """
  { init : flags -> (model, Cmd msg), view : model -> Html msg, update : msg -> model -> (model, Cmd msg), subscriptions : model -> Sub msg } -> Program flags model msg
  """

  @sandbox """
  { init : model, view : model -> Html msg, update : msg -> model -> model } -> Program () model msg
  """

  @application """
  { init : flags -> Url -> Key -> (model, Cmd msg), view : model -> { title : String, body : List (Html msg) }, update : msg -> model -> (model, Cmd msg), subscriptions : model -> Sub msg, onUrlRequest : UrlRequest -> msg, onUrlChange : Url -> msg } -> Program flags model msg
  """

  @document """
  { init : flags -> (model, Cmd msg), view : model -> { title : String, body : List (Html msg) }, update : msg -> model -> (model, Cmd msg), subscriptions : model -> Sub msg } -> Program flags model msg
  """

  @node "List (Attribute msg) -> List (Html msg) -> Html msg"
  @string_attr "String -> Attribute msg"
  @bool_attr "Bool -> Attribute msg"

  @signatures %{
    "Html.text" => "String -> Html msg",
    "Html.map" => "(a -> b) -> Html a -> Html b",
    "Html.node" => "String -> List (Attribute msg) -> List (Html msg) -> Html msg",
    "Html.Keyed.node" => "String -> List (Attribute msg) -> List (String, Html msg) -> Html msg",
    "Html.lazy" => "(a -> Html msg) -> a -> Html msg",
    "Browser.element" => @element,
    "Browser.sandbox" => @sandbox,
    "Browser.application" => @application,
    "Browser.document" => @document,
    "Browser.Dom.focus" => "String -> Task Browser.Dom.Error ()",
    "Browser.Dom.blur" => "String -> Task Browser.Dom.Error ()",
    "Browser.Dom.getViewport" => "Task Browser.Dom.Error Browser.Dom.Viewport",
    "Browser.Dom.getViewportOf" => "String -> Task Browser.Dom.Error Browser.Dom.Viewport",
    "Browser.Dom.setViewport" => "Float -> Float -> Task Browser.Dom.Error ()",
    "Browser.Dom.setViewportOf" => "String -> Float -> Float -> Task Browser.Dom.Error ()",
    "Browser.Dom.getElement" => "String -> Task Browser.Dom.Error Browser.Dom.Element",
    "Browser.Dom.setTitle" => "String -> Cmd msg",
    "Browser.Events.onResize" => "(Int -> Int -> msg) -> Sub msg",
    "Browser.Events.onVisibilityChange" => "(Visibility -> msg) -> Sub msg",
    "Browser.Events.onAnimationFrame" => "(Posix -> msg) -> Sub msg",
    "Browser.Events.onKeyDown" => "Decoder msg -> Sub msg",
    "Browser.Events.onKeyUp" => "Decoder msg -> Sub msg",
    "Browser.Events.onMouseDown" => "Decoder msg -> Sub msg",
    "Browser.Events.onMouseUp" => "Decoder msg -> Sub msg",
    "Browser.Events.onClick" => "Decoder msg -> Sub msg",
    "Browser.Navigation.pushUrl" => "Key -> String -> Cmd msg",
    "Browser.Navigation.replaceUrl" => "Key -> String -> Cmd msg",
    "Browser.Navigation.back" => "Key -> Int -> Cmd msg",
    "Browser.Navigation.forward" => "Key -> Int -> Cmd msg",
    "Browser.Navigation.load" => "String -> Cmd msg",
    "Browser.Navigation.reload" => "Cmd msg",
    "Browser.Navigation.reloadAndSkipCache" => "Cmd msg",
    "Browser.Navigation.go" => "Key -> Int -> Cmd msg",
    "Http.get" => "{ url : String, expect : Expect msg } -> Cmd msg",
    "Http.post" => "{ url : String, body : Body, expect : Expect msg } -> Cmd msg",
    "Http.request" =>
      "{ method : String, headers : List Header, url : String, body : Body, expect : Expect msg, timeout : Maybe Float, tracker : Maybe String } -> Cmd msg",
    "Http.expectString" => "(Result Http.Error String -> msg) -> Expect msg",
    "Http.expectJson" => "(Result Http.Error a -> msg) -> Decoder a -> Expect msg",
    "Http.expectBytes" => "(Result Http.Error a -> msg) -> Bytes.Decode.Decoder a -> Expect msg",
    "Http.expectWhatever" => "(Result Http.Error () -> msg) -> Expect msg",
    "Http.expectStringResponse" =>
      "(Result x a -> msg) -> (Response String -> Result x a) -> Expect msg",
    "Http.expectBytesResponse" =>
      "(Result x a -> msg) -> (Response Bytes -> Result x a) -> Expect msg",
    "Http.emptyBody" => "Body",
    "Http.jsonBody" => "Value -> Body",
    "Http.stringBody" => "String -> String -> Body",
    "Http.bytesBody" => "String -> Bytes -> Body",
    "Http.multipartBody" => "List Part -> Body",
    "Http.stringPart" => "String -> String -> Part",
    "Http.filePart" => "String -> File -> Part",
    "Http.bytesPart" => "String -> String -> Bytes -> Part",
    "Http.header" => "String -> String -> Header",
    "Http.riskyRequest" =>
      "{ method : String, headers : List Header, url : String, body : Body, expect : Expect msg, timeout : Maybe Float, tracker : Maybe String } -> Cmd msg",
    "Http.riskyTask" =>
      "{ method : String, headers : List Header, url : String, body : Body, resolver : Resolver x a, timeout : Maybe Float } -> Task x a",
    "Http.stringResolver" => "(Response String -> Result x a) -> Resolver x a",
    "Http.bytesResolver" => "(Response Bytes -> Result x a) -> Resolver x a",
    "Http.track" => "String -> (Progress -> msg) -> Sub msg",
    "Http.cancel" => "String -> Cmd msg",
    "File.name" => "File -> String",
    "File.mime" => "File -> String",
    "File.size" => "File -> Int",
    "File.toString" => "File -> Task x String",
    "File.toUrl" => "File -> Task x String",
    "File.toBytes" => "File -> Task x Bytes",
    "File.Select.file" => "List String -> (File -> msg) -> Cmd msg",
    "File.Select.files" => "List String -> (File -> List File -> msg) -> Cmd msg",
    "File.Download.string" => "String -> String -> String -> Cmd msg",
    "File.Download.bytes" => "String -> String -> Bytes -> Cmd msg",
    "File.Download.url" => "String -> Cmd msg",
    "Svg.text" => "String -> Html msg",
    "Svg.map" => "(a -> b) -> Html a -> Html b",
    "Svg.node" => "String -> List (Attribute msg) -> List (Html msg) -> Html msg",
    "Svg.Keyed.node" => "String -> List (Attribute msg) -> List (String, Html msg) -> Html msg",
    "Svg.Attributes.xlinkHref" => @string_attr,
    "Svg.Attributes.xmlSpace" => @string_attr,
    "Bytes.width" => "Bytes -> Int",
    "Bytes.getStringWidth" => "String -> Maybe Int",
    "Bytes.Decode.decode" => "Bytes.Decode.Decoder a -> Bytes -> Maybe a",
    "Bytes.Decode.unsignedInt8" => "Bytes.Decode.Decoder Int",
    "Bytes.Decode.signedInt8" => "Bytes.Decode.Decoder Int",
    "Bytes.Decode.unsignedInt16" => "Endianness -> Bytes.Decode.Decoder Int",
    "Bytes.Decode.signedInt16" => "Endianness -> Bytes.Decode.Decoder Int",
    "Bytes.Decode.unsignedInt32" => "Endianness -> Bytes.Decode.Decoder Int",
    "Bytes.Decode.signedInt32" => "Endianness -> Bytes.Decode.Decoder Int",
    "Bytes.Decode.float32" => "Endianness -> Bytes.Decode.Decoder Float",
    "Bytes.Decode.float64" => "Endianness -> Bytes.Decode.Decoder Float",
    "Bytes.Decode.string" => "Int -> Bytes.Decode.Decoder String",
    "Bytes.Decode.bytes" => "Int -> Bytes.Decode.Decoder Bytes",
    "Bytes.Decode.succeed" => "a -> Bytes.Decode.Decoder a",
    "Bytes.Decode.fail" => "Bytes.Decode.Decoder a",
    "Bytes.Decode.map" => "(a -> b) -> Bytes.Decode.Decoder a -> Bytes.Decode.Decoder b",
    "Bytes.Decode.andThen" =>
      "(a -> Bytes.Decode.Decoder b) -> Bytes.Decode.Decoder a -> Bytes.Decode.Decoder b",
    "Bytes.Encode.encode" => "Bytes.Encode.Encoder -> Bytes",
    "Bytes.Encode.unsignedInt8" => "Int -> Bytes.Encode.Encoder",
    "Bytes.Encode.signedInt8" => "Int -> Bytes.Encode.Encoder",
    "Bytes.Encode.unsignedInt16" => "Endianness -> Int -> Bytes.Encode.Encoder",
    "Bytes.Encode.signedInt16" => "Endianness -> Int -> Bytes.Encode.Encoder",
    "Bytes.Encode.unsignedInt32" => "Endianness -> Int -> Bytes.Encode.Encoder",
    "Bytes.Encode.signedInt32" => "Endianness -> Int -> Bytes.Encode.Encoder",
    "Bytes.Encode.float32" => "Endianness -> Float -> Bytes.Encode.Encoder",
    "Bytes.Encode.float64" => "Endianness -> Float -> Bytes.Encode.Encoder",
    "Bytes.Encode.string" => "String -> Bytes.Encode.Encoder",
    "Bytes.Encode.sequence" => "List Bytes.Encode.Encoder -> Bytes.Encode.Encoder",
    "Url.toString" => "Url -> String",
    "Url.fromString" => "String -> Maybe Url",
    "Url.percentEncode" => "String -> String",
    "Url.percentDecode" => "String -> Maybe String",
    "Url.Builder.absolute" => "List String -> List QueryParameter -> String",
    "Url.Builder.relative" => "List String -> List QueryParameter -> String",
    "Url.Builder.crossOrigin" => "String -> List String -> List QueryParameter -> String",
    "Url.Builder.string" => "String -> String -> QueryParameter",
    "Url.Builder.int" => "String -> Int -> QueryParameter"
  }

  @html_nodes ~w(
    div button input form a p span h1 h2 h3 img br hr ul ol li table tr td th
    header footer main_ nav section article aside canvas code pre textarea
    select option label
  )

  @html_string_attrs ~w(
    class id href src alt title type_ value name placeholder for action method
    target rel download media style width height
  )

  @html_bool_attrs ~w(checked disabled hidden selected readonly required autofocus)

  @html_msg_events ~w(
    onClick onSubmit onDoubleClick onMouseDown onMouseUp
    onMouseEnter onMouseLeave onMouseOver onMouseOut onFocus onBlur
  )

  @svg_nodes ~w(svg rect circle image text_ g path line polyline polygon ellipse)

  @svg_string_attrs ~w(
    fill stroke width height x y cx cy r dx dy d transform viewBox
    fontSize textAnchor id class
  )

  @constructors [
    {"Http.BadUrl", "Http.Error", 1, "String -> Http.Error"},
    {"Http.Timeout", "Http.Error", 0, "Http.Error"},
    {"Http.NetworkError", "Http.Error", 0, "Http.Error"},
    {"Http.BadStatus", "Http.Error", 1, "Int -> Http.Error"},
    {"Http.BadBody", "Http.Error", 1, "String -> Http.Error"},
    {"Browser.Internal", "Browser.UrlRequest", 1, "Url -> Browser.UrlRequest"},
    {"Browser.External", "Browser.UrlRequest", 1, "String -> Browser.UrlRequest"},
    {"Browser.Events.Visible", "Browser.Events.Visibility", 0, "Browser.Events.Visibility"},
    {"Browser.Events.Hidden", "Browser.Events.Visibility", 0, "Browser.Events.Visibility"},
    {"Http.Sending", "Http.Progress", 1, "{ sent : Int, size : Int } -> Http.Progress"},
    {"Http.Receiving", "Http.Progress", 1, "{ received : Int, size : Maybe Int } -> Http.Progress"},
    {"Http.BadUrl_", "Http.Response", 1, "String -> Http.Response body"},
    {"Http.Timeout_", "Http.Response", 0, "Http.Response body"},
    {"Http.NetworkError_", "Http.Response", 0, "Http.Response body"},
    {"Http.BadStatus_", "Http.Response", 2,
     "{ url : String, statusCode : Int, statusText : String, headers : Dict String String } -> body -> Http.Response body"},
    {"Http.GoodStatus_", "Http.Response", 2,
     "{ url : String, statusCode : Int, statusText : String, headers : Dict String String } -> body -> Http.Response body"},
    {"Browser.Dom.NotFound", "Browser.Dom.Error", 1, "String -> Browser.Dom.Error"},
    {"Url.Http", "Url.Protocol", 0, "Url.Protocol"},
    {"Url.Https", "Url.Protocol", 0, "Url.Protocol"},
    {"Bytes.LE", "Bytes.Endianness", 0, "Bytes.Endianness"},
    {"Bytes.BE", "Bytes.Endianness", 0, "Bytes.Endianness"},
    {"LE", "Bytes.Endianness", 0, "Bytes.Endianness"},
    {"BE", "Bytes.Endianness", 0, "Bytes.Endianness"}
  ]

  @known_arities %{
    "Html" => 1,
    "Html.Html" => 1,
    "Html.Attribute" => 1,
    "Attribute" => 1,
    "VirtualDom.Node" => 1,
    "Svg" => 1,
    "Svg.Svg" => 1,
    "Http.Request" => 1,
    "Http.Expect" => 1,
    "Http.Resolver" => 2,
    "Http.Response" => 1,
    "Bytes" => 0,
    "Bytes.Bytes" => 0,
    "Bytes.Decode.Decoder" => 1,
    "Bytes.Encode.Encoder" => 0,
    "Bytes.Endianness" => 0,
    "Endianness" => 0,
    "Url.Protocol" => 0,
    "File" => 0,
    "File.File" => 0,
    "Url" => 0,
    "Url.Url" => 0,
    "Browser.UrlRequest" => 0,
    "UrlRequest" => 0,
    "Browser.Navigation.Key" => 0,
    "Key" => 0,
    "Browser.Dom.Error" => 0,
    "Browser.Dom.Viewport" => 0,
    "Browser.Dom.Element" => 0,
    "Program" => 3
  }

  @spec install(Env.t()) :: Env.t()
  def install(env) do
    env
    |> install_known_arities()
    |> install_aliases()
    |> install_dom_aliases()
    |> install_url_bytes_aliases()
    |> install_signatures()
    |> install_nodes()
    |> install_attributes()
    |> install_constructors()
    |> install_call_shorthands()
  end

  defp install_known_arities(env) do
    types =
      Enum.reduce(@known_arities, env.types, fn {name, arity}, types ->
        Map.put_new(types, name, %{arity: arity, kind: :opaque})
      end)

    %{env | types: types}
  end

  defp install_aliases(env) do
    Enum.reduce(
      [
        {"Html", "Html.Html", 1},
        {"Svg", "Html.Html", 1},
        {"Svg.Svg", "Html.Html", 1},
        {"Attribute", "Html.Attribute", 1},
        {"File", "File.File", 0},
        {"Url", "Url.Url", 0},
        {"UrlRequest", "Browser.UrlRequest", 0},
        {"Browser.UrlRequest", "Browser.UrlRequest", 0},
        {"Bytes", "Bytes.Bytes", 0},
        {"Key", "Browser.Navigation.Key", 0}
      ],
      env,
      fn {short, qualified, arity}, acc ->
        params = if arity == 1, do: ["msg"], else: []

        args =
          Enum.map(params, fn param ->
            case Parser.parse(param) do
              {:ok, t} -> t
              _ -> Type.var(1)
            end
          end)

        body = Type.named(qualified, args)

        Env.put_alias(acc, short, %{
          name: qualified,
          params: params,
          body: body,
          fields: %{}
        })
      end
    )
  end

  defp install_signatures(env) do
    Enum.reduce(@signatures, env, fn {name, src}, acc ->
      put_parsed(acc, name, src)
    end)
  end

  defp install_nodes(env) do
    env =
      Enum.reduce(@html_nodes, env, fn name, acc ->
        put_parsed(acc, "Html.#{name}", @node)
      end)

    Enum.reduce(@svg_nodes, env, fn name, acc ->
      put_parsed(acc, "Svg.#{name}", @node)
    end)
  end

  defp install_attributes(env) do
    env =
      Enum.reduce(@html_string_attrs, env, fn name, acc ->
        acc
        |> put_parsed("Html.Attributes.#{name}", @string_attr)
        |> put_parsed("Svg.Attributes.#{name}", @string_attr)
      end)

    env =
      Enum.reduce(@html_bool_attrs, env, fn name, acc ->
        put_parsed(acc, "Html.Attributes.#{name}", @bool_attr)
      end)

    env =
      Enum.reduce(@html_msg_events, env, fn name, acc ->
        put_parsed(acc, "Html.Events.#{name}", "msg -> Attribute msg")
      end)

    env =
      env
      |> put_parsed("Html.Events.onInput", "(String -> msg) -> Attribute msg")
      |> put_parsed("Html.Events.onCheck", "(Bool -> msg) -> Attribute msg")

    env =
      env
      |> put_parsed("Html.Attributes.classList", "List (String, Bool) -> Attribute msg")
      |> put_parsed("Html.Attributes.style", "String -> String -> Attribute msg")
      |> put_parsed("Html.Events.on", "String -> Decoder msg -> Attribute msg")

    Enum.reduce(@svg_string_attrs, env, fn name, acc ->
      put_parsed(acc, "Svg.Attributes.#{name}", @string_attr)
    end)
  end

  defp install_constructors(env) do
    Enum.reduce(@constructors, env, fn {name, union, arity, src}, acc ->
      case Parser.parse(src) do
        {:ok, type} ->
          scheme = Env.generalize(acc, type)

          info = %{
            name: name,
            union: union,
            arity: arity,
            scheme: scheme
          }

          acc
          |> Map.update!(:constructors, &Map.put(&1, name, info))
          |> Env.put_value(name, scheme)

        {:error, _} ->
          acc
      end
    end)
  end

  defp put_parsed(env, name, src) do
    case Parser.parse(src) do
      {:ok, type} -> Env.put_value(env, name, Env.generalize(env, type))
      {:error, _} -> env
    end
  end

  @viewport_src """
  { scene : { width : Float, height : Float }, viewport : { x : Float, y : Float, width : Float, height : Float } }
  """

  @element_src """
  { scene : { width : Float, height : Float }, viewport : { x : Float, y : Float, width : Float, height : Float }, element : { x : Float, y : Float, width : Float, height : Float } }
  """

  defp install_dom_aliases(env) do
    env
    |> put_type_alias("Browser.Dom.Viewport", @viewport_src)
    |> put_type_alias("Viewport", @viewport_src)
    |> put_type_alias("Browser.Dom.Element", @element_src)
    |> put_type_alias("Element", @element_src)
  end

  @url_src """
  { protocol : Url.Protocol, host : String, port_ : Maybe Int, path : String, query : Maybe String, fragment : Maybe String }
  """

  defp install_url_bytes_aliases(env) do
    env
    |> put_type_alias("Url.Url", @url_src)
    |> put_type_alias("Url", @url_src)
    |> Env.put_alias("Endianness", %{
      name: "Bytes.Endianness",
      params: [],
      body: Type.named("Bytes.Endianness"),
      fields: %{}
    })
  end

  defp put_type_alias(env, name, src) do
    case Parser.parse(src) do
      {:ok, {:record, fields, _} = body} ->
        Env.put_alias(env, name, %{name: name, params: [], body: body, fields: fields})

      {:ok, body} ->
        Env.put_alias(env, name, %{name: name, params: [], body: body, fields: %{}})

      {:error, _} ->
        env
    end
  end

  @call_shorthands [
    {"Http.expectString", "(String -> msg) -> Expect msg"},
    {"Browser.Navigation.reload", "Key -> Cmd msg"},
    {"Browser.Navigation.reloadAndSkipCache", "Key -> Cmd msg"}
  ]

  defp install_call_shorthands(env) do
    Enum.reduce(@call_shorthands, env, fn {name, src}, acc ->
      case Parser.parse(src) do
        {:ok, type} -> Env.put_alt(acc, name, Env.generalize(acc, type))
        {:error, _} -> acc
      end
    end)
  end
end
