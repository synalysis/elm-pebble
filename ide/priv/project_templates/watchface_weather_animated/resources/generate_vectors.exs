# Run from the ide app root:
#   mix run priv/project_templates/watchface_weather_animated/resources/generate_vectors.exs

alias Ide.Resources.{CtorNaming, PdcDecoder, PdcEncoder, SvgConverter}

script_dir = Path.dirname(Path.expand(__ENV__.file))
vectors_dir = Path.join(script_dir, "vectors")
manifest_path = Path.join(script_dir, "vectors.json")
frame_duration_ms = 100

conditions = [
  "Clear",
  "Cloudy",
  "Fog",
  "Drizzle",
  "Rain",
  "Snow",
  "Showers",
  "Storm",
  "Unknown"
]

cloud_large = """
<circle cx="20" cy="26" r="8" fill="black"/>
<circle cx="28" cy="24" r="9" fill="black"/>
<circle cx="34" cy="27" r="7" fill="black"/>
"""

cloud_small = """
<circle cx="22" cy="26" r="6" fill="black"/>
<circle cx="28" cy="24" r="7" fill="black"/>
<circle cx="32" cy="26" r="5" fill="black"/>
"""

wrap = fn body ->
  """
  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  #{body}
  </svg>
  """
end

condition_svg = %{
  "Clear" =>
    wrap.("""
    <circle cx="24" cy="24" r="8" fill="black"/>
    <line x1="35" y1="24" x2="39" y2="24" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="31.8" y1="31.8" x2="34.6" y2="34.6" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="24" y1="35" x2="24" y2="39" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="16.2" y1="31.8" x2="13.4" y2="34.6" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="13" y1="24" x2="9" y2="24" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="16.2" y1="16.2" x2="13.4" y2="13.4" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="24" y1="13" x2="24" y2="9" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="31.8" y1="16.2" x2="34.6" y2="13.4" stroke="black" stroke-width="2" stroke-linecap="round"/>
    """),
  "Cloudy" => wrap.(cloud_large),
  "Fog" =>
    wrap.("""
    <rect x="10" y="18" width="28" height="3" fill="black"/>
    <rect x="10" y="24" width="28" height="3" fill="black"/>
    <rect x="10" y="30" width="28" height="3" fill="black"/>
    """),
  "Drizzle" =>
    wrap.("""
    #{cloud_small}
    <line x1="20" y1="32" x2="20" y2="36" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="24" y1="32" x2="24" y2="36" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="28" y1="32" x2="28" y2="36" stroke="black" stroke-width="2" stroke-linecap="round"/>
    """),
  "Rain" =>
    wrap.("""
    #{cloud_large}
    <line x1="18" y1="32" x2="18" y2="40" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="22" y1="32" x2="22" y2="40" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="26" y1="32" x2="26" y2="40" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="30" y1="32" x2="30" y2="40" stroke="black" stroke-width="2" stroke-linecap="round"/>
    """),
  "Snow" =>
    wrap.("""
    #{cloud_large}
    <line x1="18" y1="33" x2="18" y2="39" stroke="black" stroke-width="1.5" stroke-linecap="round"/>
    <line x1="15" y1="36" x2="21" y2="36" stroke="black" stroke-width="1.5" stroke-linecap="round"/>
    <line x1="24" y1="35" x2="24" y2="41" stroke="black" stroke-width="1.5" stroke-linecap="round"/>
    <line x1="21" y1="38" x2="27" y2="38" stroke="black" stroke-width="1.5" stroke-linecap="round"/>
    <line x1="30" y1="33" x2="30" y2="39" stroke="black" stroke-width="1.5" stroke-linecap="round"/>
    <line x1="27" y1="36" x2="33" y2="36" stroke="black" stroke-width="1.5" stroke-linecap="round"/>
    """),
  "Showers" =>
    wrap.("""
    #{cloud_large}
    <line x1="18" y1="32" x2="15" y2="38" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="22" y1="33" x2="19" y2="39" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="26" y1="32" x2="23" y2="38" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="30" y1="33" x2="27" y2="39" stroke="black" stroke-width="2" stroke-linecap="round"/>
    """),
  "Storm" =>
    wrap.("""
    #{cloud_large}
    <line x1="26" y1="30" x2="22" y2="38" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="22" y1="38" x2="24" y2="38" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="24" y1="38" x2="21" y2="46" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="21" y1="46" x2="29" y2="36" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="29" y1="36" x2="26" y2="36" stroke="black" stroke-width="2" stroke-linecap="round"/>
    <line x1="26" y1="36" x2="29" y2="30" stroke="black" stroke-width="2" stroke-linecap="round"/>
    """),
  "Unknown" =>
    wrap.("""
    #{cloud_large}
    <circle cx="24" cy="24" r="5" fill="black"/>
    <line x1="24" y1="21" x2="24" y2="27" stroke="white" stroke-width="2" stroke-linecap="round"/>
    <circle cx="24" cy="29" r="1.2" fill="white"/>
    """)
}

convert_image = fn svg, pdc_path ->
  {:ok, %{bytes: bytes}} = SvgConverter.convert_svg_string(svg)
  :ok = File.write!(pdc_path, bytes)
  byte_size(bytes)
end

convert_sequence = fn frames, pdc_path ->
  images =
    Enum.map(frames, fn svg ->
      {:ok, %{bytes: bytes}} = SvgConverter.convert_svg_string(svg)
      {:ok, image} = PdcDecoder.decode(bytes)
      image
    end)

  {:ok, bytes} = PdcEncoder.encode_sequence(images, frame_duration_ms: frame_duration_ms)
  :ok = File.write!(pdc_path, bytes)
  byte_size(bytes)
end

File.mkdir_p!(vectors_dir)

manifest_entries =
  for condition <- conditions do
    ctor = CtorNaming.ctor(:vector_static, "Weather#{condition}")
    pdc_path = Path.join(vectors_dir, "#{ctor}.pdc")
    size = convert_image.(Map.fetch!(condition_svg, condition), pdc_path)
    IO.puts("Wrote #{pdc_path} (#{size} bytes)")

    %{
      "id" => "vector_#{String.downcase(ctor)}",
      "base_name" => CtorNaming.legacy_base_from_ctor(ctor, :vector_static),
      "ctor" => ctor,
      "filename" => "#{ctor}.pdc",
      "mime" => "application/octet-stream",
      "bytes" => size,
      "source" => "pdc",
      "kind" => "image"
    }
  end

transition_entries =
  for source <- conditions,
      source != "Unknown",
      target <- conditions,
      target != "Unknown",
      source != target do
    ctor = CtorNaming.ctor(:vector_animated, "Transition#{source}To#{target}")
    pdc_path = Path.join(vectors_dir, "#{ctor}.pdc")

    size =
      convert_sequence.(
        [Map.fetch!(condition_svg, source), Map.fetch!(condition_svg, target)],
        pdc_path
      )

    IO.puts("Wrote #{pdc_path} (#{size} bytes)")

    %{
      "id" => "vector_#{String.downcase(ctor)}",
      "base_name" => CtorNaming.legacy_base_from_ctor(ctor, :vector_animated),
      "ctor" => ctor,
      "filename" => "#{ctor}.pdc",
      "mime" => "application/octet-stream",
      "bytes" => size,
      "source" => "pdc",
      "kind" => "sequence",
      "frames" => 2,
      "frame_duration_ms" => frame_duration_ms
    }
  end

manifest = %{
  "schema_version" => 1,
  "entries" => manifest_entries ++ transition_entries
}

File.write!(manifest_path, Jason.encode!(manifest, pretty: true) <> "\n")
IO.puts("Wrote #{manifest_path} (#{length(manifest["entries"])} entries)")
