defmodule ElmEx.Frontend.GlslLiteralTest do
  use ExUnit.Case, async: true

  alias ElmEx.Frontend.GeneratedExpressionParser
  alias ElmEx.Frontend.GeneratedParser

  @glsl_source """
  [glsl|
      attribute vec3 position;
      uniform mat4 view;
      void main () {
          gl_Position = view * vec4(position, 1.0);
      }
  |]
  """

  test "parses a [glsl| ... |] literal into a record_literal with src/attributes/uniforms" do
    assert {:ok, %{op: :record_literal, fields: fields}} =
             GeneratedExpressionParser.parse(@glsl_source)

    field_names = Enum.map(fields, & &1.name)
    assert field_names == ["src", "attributes", "uniforms"]

    src_field = Enum.find(fields, &(&1.name == "src"))
    assert %{op: :string_literal, value: src} = src_field.expr
    assert src =~ "position"
    assert src =~ "void main"

    attributes_field = Enum.find(fields, &(&1.name == "attributes"))
    assert %{op: :record_literal, fields: attribute_fields} = attributes_field.expr
    assert Enum.map(attribute_fields, & &1.name) == ["position"]
    assert Enum.map(attribute_fields, & &1.expr) == [%{op: :string_literal, value: "position"}]

    uniforms_field = Enum.find(fields, &(&1.name == "uniforms"))
    assert %{op: :record_literal, fields: uniform_fields} = uniforms_field.expr
    assert Enum.map(uniform_fields, & &1.name) == ["view"]
    assert Enum.map(uniform_fields, & &1.expr) == [%{op: :string_literal, value: "view"}]
  end

  test "extracts multiple attributes/uniforms and honors precision qualifiers" do
    source = """
    [glsl|
        precision highp float;
        attribute highp vec3 position;
        attribute mediump vec2 uv;
        uniform highp mat4 modelMatrix;
        uniform lowp vec4 modelScale;
        void main() {}
    |]
    """

    assert {:ok, %{op: :record_literal, fields: fields}} =
             GeneratedExpressionParser.parse(source)

    attributes_field = Enum.find(fields, &(&1.name == "attributes"))
    uniforms_field = Enum.find(fields, &(&1.name == "uniforms"))

    assert Enum.map(attributes_field.expr.fields, & &1.name) == ["position", "uv"]
    assert Enum.map(uniforms_field.expr.fields, & &1.name) == ["modelMatrix", "modelScale"]
  end

  test "allows `|` characters inside the GLSL body as long as they are not `|]`" do
    source = """
    [glsl|
        void main() {
            bool ok = true || false;
        }
    |]
    """

    assert {:ok, %{op: :record_literal, fields: fields}} =
             GeneratedExpressionParser.parse(source)

    src_field = Enum.find(fields, &(&1.name == "src"))
    assert src_field.expr.value =~ "true || false"
  end

  test "non-glsl sources are unaffected" do
    assert {:ok, %{op: :int_literal, value: 1}} = GeneratedExpressionParser.parse("1")
  end

  test "a full module with a [glsl| ... |] shader passes AST contract validation" do
    source = """
    module ShaderFixture exposing (shader)


    shader =
        [glsl|
            attribute vec3 position;
            uniform mat4 view;
            void main () {
                gl_Position = view * vec4(position, 1.0);
            }
        |]
    """

    assert {:ok, module} = GeneratedParser.parse_source("ShaderFixture.elm", source)

    decl = Enum.find(module.declarations, &(&1[:kind] == :function_definition and &1[:name] == "shader"))
    assert %{op: :record_literal, fields: fields} = decl.expr
    assert Enum.map(fields, & &1.name) == ["src", "attributes", "uniforms"]
  end
end
