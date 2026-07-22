/**
 * Host implementation of elm-explorations/webgl's Elm.Kernel.WebGL for elmc WASM.
 *
 * Ports `_WebGL_entity`, `_WebGL_toHtml`, and the draw/render/diff path onto the
 * RC handle store. Shaders are `{attributes, src, uniforms}` records (alphabetical
 * field order). Vectors/matrices arrive as TAG_MJS Float64Arrays.
 *
 * VirtualDom.custom is represented as TAG_VDOM kind "custom" with customKind
 * "webgl"; render/diff live entirely on the host (no WASM function pointers).
 */

export function createWebglRuntime(deps) {
  const {
    allocHandle,
    readHandle,
    retain,
    listItems,
    stringValue,
    asHandle,
    TAG_VDOM,
    TAG_RECORD,
    TAG_TUPLE2,
    TAG_LIST,
    TAG_INT,
    TAG_FLOAT,
    TAG_STRING,
    TAG_MJS,
    TAG_WEBGL_ENTITY,
  } = deps;

  let shaderGuid = 1;
  const rAF =
    typeof requestAnimationFrame !== "undefined"
      ? requestAnimationFrame
      : (cb) => setTimeout(cb, 1000 / 60);

  const numberValue = (ptr) => {
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_FLOAT) return payload.value;
    if (payload?.tag === TAG_INT) return payload.value;
    return 0;
  };

  const boolValue = (ptr) => {
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_INT) return (payload.value | 0) !== 0;
    return Boolean(ptr);
  };

  const recordFields = (ptr) => readHandle(ptr)?.fields ?? [];

  // Identity name-maps from shader records store only values (alphabetical).
  // For `{position: "position"}` that is just the list of names.
  const identityNameList = (mapPtr) => {
    const fields = recordFields(mapPtr);
    return fields.map((f) => stringValue(f)).filter((n) => typeof n === "string" && n.length > 0);
  };

  const shaderParts = (shaderPtr) => {
    // Alphabetical: attributes, src, uniforms
    const fields = recordFields(shaderPtr);
    return {
      attributes: identityNameList(fields[0]),
      attributesPtr: fields[0] | 0,
      src: stringValue(fields[1] ?? 0),
      uniforms: identityNameList(fields[2]),
      uniformsPtr: fields[2] | 0,
      id: readHandle(shaderPtr)?.__webglShaderId ?? 0,
      ptr: shaderPtr | 0,
    };
  };

  const assignShaderId = (shaderPtr) => {
    const payload = readHandle(shaderPtr);
    if (!payload) return 0;
    if (!payload.__webglShaderId) {
      payload.__webglShaderId = shaderGuid++;
    }
    return payload.__webglShaderId;
  };

  const entity = (settingsPtr, vertPtr, fragPtr, meshPtr, uniformsPtr) => {
    const settings = asHandle(settingsPtr);
    const vert = asHandle(vertPtr);
    const frag = asHandle(fragPtr);
    const mesh = asHandle(meshPtr);
    const uniforms = asHandle(uniformsPtr);
    for (const ptr of [settings, vert, frag, mesh, uniforms]) {
      if (ptr) retain(null, ptr);
    }
    return allocHandle({
      tag: TAG_WEBGL_ENTITY,
      settings,
      vert,
      frag,
      mesh,
      uniforms,
    });
  };

  const factsFromList = (factsPtr) => {
    const attrs = [];
    for (const item of listItems(factsPtr)) {
      const payload = readHandle(item);
      if (payload?.tag !== TAG_VDOM) continue;
      if (payload.kind === "attr" || payload.kind === "property" || payload.kind === "event") {
        attrs.push(payload);
      } else if (payload.kind === "style" || payload.name === "style") {
        attrs.push(payload);
      }
    }
    return attrs;
  };

  const toHtml = (optionsPtr, factsPtr, entitiesPtr) => {
    const options = asHandle(optionsPtr);
    const entities = asHandle(entitiesPtr);
    const facts = factsFromList(factsPtr);
    if (options) retain(null, options);
    if (entities) retain(null, entities);
    return allocHandle({
      tag: TAG_VDOM,
      kind: "custom",
      renderKey: "webgl",
      facts,
      // Host model: entities/options handles + draw cache (survives patches).
      model: { entities, options, cache: null },
    });
  };

  const applyFacts = (el, facts) => {
    if (!el || !facts) return;
    let styleText = "";
    for (const attr of facts) {
      if (!attr) continue;
      if (attr.kind === "property") {
        const prop = attr.name;
        const value = attr.value;
        if (prop === "width" || prop === "height") {
          const n = typeof value === "number" ? value : parseInt(String(value), 10);
          if (Number.isFinite(n)) {
            el[prop] = n;
            continue;
          }
        }
        el[prop] = value;
        continue;
      }
      if (attr.name === "style") {
        styleText += attr.value ?? "";
        continue;
      }
      if (attr.name) {
        el.setAttribute(attr.name, attr.value ?? "");
      }
    }
    if (styleText) el.setAttribute("style", styleText);
  };

  const decodeOptions = (optionsPtr) => {
    const contextAttributes = {
      alpha: false,
      depth: false,
      stencil: false,
      antialias: false,
      premultipliedAlpha: false,
      preserveDrawingBuffer: false,
    };
    const sceneSettings = [];

    for (const optPtr of listItems(optionsPtr)) {
      const payload = readHandle(optPtr);
      if (!payload) continue;

      // Nullary options (Antialias, PreserveDrawingBuffer) may be bare TAG_INT tags.
      if (payload.tag === TAG_INT) {
        // Best-effort: Scene3d always includes depth/clearColor/alpha; treat lone
        // ints as antialias enable.
        contextAttributes.antialias = true;
        continue;
      }

      if (payload.tag !== TAG_TUPLE2) continue;
      const tag = numberValue(payload.first) | 0;
      const body = payload.second | 0;
      const bodyPayload = readHandle(body);

      // Option tags (alphabetical): Alpha, Antialias, ClearColor, Depth,
      // PreserveDrawingBuffer, Stencil — 0..5 in typical manifest order.
      // Decode by payload shape rather than hardcoding tags.
      if (bodyPayload?.tag === TAG_INT || bodyPayload?.tag === TAG_FLOAT) {
        // Alpha Bool | Depth Float | Stencil Int
        const n = numberValue(body);
        if (bodyPayload.tag === TAG_INT && (n === 0 || n === 1) && tag <= 1) {
          contextAttributes.alpha = true;
          contextAttributes.premultipliedAlpha = n !== 0;
        } else if (bodyPayload.tag === TAG_FLOAT || (bodyPayload.tag === TAG_INT && n > 1)) {
          contextAttributes.depth = true;
          sceneSettings.push((gl) => gl.clearDepth(n));
        } else {
          contextAttributes.stencil = true;
          sceneSettings.push((gl) => gl.clearStencil(n | 0));
        }
        continue;
      }

      // ClearColor Float Float Float Float → nested tuple chain of 4 floats
      const floats = flattenNumericTuple(body);
      if (floats.length >= 4) {
        const [r, g, b, a] = floats;
        sceneSettings.push((gl) => gl.clearColor(r, g, b, a));
        continue;
      }

      // Nullary-ish payload (unit / empty): Antialias or PreserveDrawingBuffer
      if (!bodyPayload || (bodyPayload.tag === TAG_INT && bodyPayload.value === 0)) {
        if (tag % 2 === 0) contextAttributes.antialias = true;
        else contextAttributes.preserveDrawingBuffer = true;
      }
    }

    // Scene3d defaults when options list is empty / undecodable.
    if (!contextAttributes.depth && sceneSettings.length === 0) {
      contextAttributes.depth = true;
      contextAttributes.alpha = true;
      contextAttributes.premultipliedAlpha = true;
      contextAttributes.antialias = true;
      sceneSettings.push((gl) => {
        gl.clearDepth(1);
        gl.clearColor(0, 0, 0, 0);
      });
    }

    return { contextAttributes, sceneSettings };
  };

  const flattenNumericTuple = (ptr) => {
    const out = [];
    const walk = (p) => {
      const payload = readHandle(p);
      if (!payload) return;
      if (payload.tag === TAG_FLOAT || payload.tag === TAG_INT) {
        out.push(numberValue(p));
        return;
      }
      if (payload.tag === TAG_TUPLE2) {
        walk(payload.first);
        walk(payload.second);
      }
    };
    walk(ptr);
    return out;
  };

  const ensureCache = (model) => {
    if (model.cache) return model.cache;
    model.cache = {
      gl: null,
      shaders: [],
      programs: {},
      lastProgId: null,
      buffers: new WeakMap(),
      textures: new WeakMap(),
      toggle: false,
      blend: { enabled: false, toggle: false },
      depthTest: { enabled: false, toggle: false, b: true },
      stencilTest: { enabled: false, toggle: false, c: 0 },
      scissor: { enabled: false, toggle: false },
      colorMask: { enabled: false, toggle: false },
      cullFace: { enabled: false, toggle: false },
      polygonOffset: { enabled: false, toggle: false },
      sampleCoverage: { enabled: false, toggle: false },
      sampleAlphaToCoverage: { enabled: false, toggle: false },
      STENCIL_WRITEMASK: 0,
    };
    return model.cache;
  };

  const doCompile = (gl, src, type) => {
    const shader = gl.createShader(type);
    gl.shaderSource(shader, "#extension GL_OES_standard_derivatives : enable\n" + (src || ""));
    gl.compileShader(shader);
    return shader;
  };

  const doLink = (gl, vshader, fshader) => {
    const program = gl.createProgram();
    gl.attachShader(program, vshader);
    gl.attachShader(program, fshader);
    gl.linkProgram(program);
    return program;
  };

  const getAttributeInfo = (gl, type) => {
    switch (type) {
      case gl.FLOAT:
        return { size: 1, arraySize: 1, type: Float32Array, baseType: gl.FLOAT };
      case gl.FLOAT_VEC2:
        return { size: 2, arraySize: 1, type: Float32Array, baseType: gl.FLOAT };
      case gl.FLOAT_VEC3:
        return { size: 3, arraySize: 1, type: Float32Array, baseType: gl.FLOAT };
      case gl.FLOAT_VEC4:
        return { size: 4, arraySize: 1, type: Float32Array, baseType: gl.FLOAT };
      case gl.FLOAT_MAT4:
        return { size: 4, arraySize: 4, type: Float32Array, baseType: gl.FLOAT };
      case gl.INT:
        return { size: 1, arraySize: 1, type: Int32Array, baseType: gl.INT };
      default:
        return null;
    }
  };

  const meshParts = (meshPtr) => {
    const payload = readHandle(meshPtr);
    if (!payload) return null;

    // Union: (tag, payload). 2-arg → (info, data); 3-arg → (info, (verts, indices))
    let body = meshPtr;
    if (payload.tag === TAG_TUPLE2) {
      body = payload.second | 0;
    }
    const bodyPayload = readHandle(body);
    if (!bodyPayload) return null;

    let infoPtr = 0;
    let dataPtr = 0;
    let indicesPtr = 0;

    if (bodyPayload.tag === TAG_TUPLE2) {
      infoPtr = bodyPayload.first | 0;
      const rest = bodyPayload.second | 0;
      const restPayload = readHandle(rest);
      if (restPayload?.tag === TAG_TUPLE2) {
        // MeshIndexed3: (vertices, indices)
        const maybeList = readHandle(restPayload.first);
        if (maybeList?.tag === TAG_LIST) {
          dataPtr = restPayload.first | 0;
          indicesPtr = restPayload.second | 0;
        } else {
          dataPtr = rest;
        }
      } else if (restPayload?.tag === TAG_LIST) {
        dataPtr = rest;
      } else {
        dataPtr = rest;
      }
    }

    // RenderInfo alphabetical: elemSize, indexSize, mode
    const infoFields = recordFields(infoPtr);
    const elemSize = numberValue(infoFields[0] ?? 0) | 0;
    const indexSize = numberValue(infoFields[1] ?? 0) | 0;
    const mode = numberValue(infoFields[2] ?? 0) | 0;

    return { elemSize, indexSize, mode, dataPtr, indicesPtr, meshPtr };
  };

  const tupleElements = (ptr, count) => {
    const out = [];
    let cur = ptr;
    for (let i = 0; i < count; i++) {
      const payload = readHandle(cur);
      if (!payload) break;
      if (payload.tag === TAG_TUPLE2 && i < count - 1) {
        out.push(payload.first | 0);
        cur = payload.second | 0;
      } else {
        out.push(cur | 0);
        break;
      }
    }
    while (out.length < count) out.push(0);
    return out;
  };

  const mjsData = (ptr) => {
    const payload = readHandle(ptr);
    if (payload?.tag === TAG_MJS && payload.data) return payload.data;
    if (payload?.tag === TAG_FLOAT || payload?.tag === TAG_INT) {
      return new Float64Array([numberValue(ptr)]);
    }
    return null;
  };

  // Vertex attribute field index from identity attribute name list (sorted).
  const attributeFieldIndex = (attrNames, elmFieldName) => {
    const sorted = [...attrNames].sort();
    return sorted.indexOf(elmFieldName);
  };

  const readAttributeComponent = (vertPtr, attrNames, elmFieldName, componentIndex) => {
    const fields = recordFields(vertPtr);
    const idx = attributeFieldIndex(attrNames, elmFieldName);
    if (idx < 0 || idx >= fields.length) return 0;
    const data = mjsData(fields[idx]);
    if (!data) return numberValue(fields[idx]);
    return data[componentIndex] ?? 0;
  };

  const listLength = (ptr) => listItems(ptr).length;

  const bindAttribute = (gl, attribute, mesh, attrNames) => {
    const attributeInfo = getAttributeInfo(gl, attribute.type);
    if (!attributeInfo) return null;

    const elmField = attribute.name;
    const elems = listItems(mesh.dataPtr);
    const dataOffset = attributeInfo.size * attributeInfo.arraySize * mesh.elemSize;
    const array = new attributeInfo.type(elems.length * dataOffset);
    let dataIdx = 0;

    for (const elemPtr of elems) {
      const verts =
        mesh.elemSize <= 1 ? [elemPtr] : tupleElements(elemPtr, mesh.elemSize);
      for (const vertPtr of verts) {
        const cnt = attributeInfo.size * attributeInfo.arraySize;
        for (let i = 0; i < cnt; i++) {
          array[dataIdx++] = readAttributeComponent(vertPtr, attrNames, elmField, i);
        }
      }
    }

    const buffer = gl.createBuffer();
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer);
    gl.bufferData(gl.ARRAY_BUFFER, array, gl.STATIC_DRAW);
    return buffer;
  };

  const makeIndexedBuffer = (indicesPtr, indexSize) => {
    const elems = listItems(indicesPtr);
    const indices = new Uint32Array(elems.length * Math.max(indexSize, 1));
    let fill = 0;
    for (const elem of elems) {
      if (indexSize <= 1) {
        indices[fill++] = numberValue(elem) | 0;
      } else {
        const parts = tupleElements(elem, indexSize);
        for (const p of parts) indices[fill++] = numberValue(p) | 0;
      }
    }
    return indices;
  };

  const bindSetup = (gl, mesh) => {
    if (mesh.indexSize > 0 && mesh.indicesPtr) {
      const indexBuffer = gl.createBuffer();
      const indices = makeIndexedBuffer(mesh.indicesPtr, mesh.indexSize);
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indices, gl.STATIC_DRAW);
      return { numIndices: indices.length, indexBuffer, buffers: {} };
    }
    return {
      numIndices: mesh.elemSize * listLength(mesh.dataPtr),
      indexBuffer: null,
      buffers: {},
    };
  };

  const uniformJsValue = (ptr) => {
    const payload = readHandle(ptr);
    if (!payload) return 0;
    if (payload.tag === TAG_MJS && payload.data) {
      return payload.data;
    }
    if (payload.tag === TAG_FLOAT || payload.tag === TAG_INT) {
      return numberValue(ptr);
    }
    return ptr;
  };

  // Uniforms record values in alphabetical order of field names from shader map.
  const uniformsByName = (uniformsPtr, uniformNames) => {
    const fields = recordFields(uniformsPtr);
    const sorted = [...uniformNames].sort();
    const out = {};
    sorted.forEach((name, i) => {
      out[name] = uniformJsValue(fields[i] ?? 0);
    });
    return out;
  };

  const createUniformSetters = (gl, cache, program, uniformNames) => {
    const glProgram = program.glProgram;
    const currentUniforms = program.currentUniforms;
    const setters = {};
    const numUniforms = gl.getProgramParameter(glProgram, gl.ACTIVE_UNIFORMS);

    for (let i = 0; i < numUniforms; i++) {
      const uniform = gl.getActiveUniform(glProgram, i);
      const location = gl.getUniformLocation(glProgram, uniform.name);
      const elmName = uniformNames.includes(uniform.name)
        ? uniform.name
        : uniform.name;
      const name = elmName;

      switch (uniform.type) {
        case gl.INT:
        case gl.BOOL:
          setters[name] = (value) => {
            const v = value | 0;
            if (currentUniforms[name] !== v) {
              gl.uniform1i(location, v);
              currentUniforms[name] = v;
            }
          };
          break;
        case gl.FLOAT:
          setters[name] = (value) => {
            const v = +value;
            if (currentUniforms[name] !== v) {
              gl.uniform1f(location, v);
              currentUniforms[name] = v;
            }
          };
          break;
        case gl.FLOAT_VEC2:
          setters[name] = (value) => {
            gl.uniform2f(location, value[0], value[1]);
            currentUniforms[name] = value;
          };
          break;
        case gl.FLOAT_VEC3:
          setters[name] = (value) => {
            gl.uniform3f(location, value[0], value[1], value[2]);
            currentUniforms[name] = value;
          };
          break;
        case gl.FLOAT_VEC4:
          setters[name] = (value) => {
            gl.uniform4f(location, value[0], value[1], value[2], value[3]);
            currentUniforms[name] = value;
          };
          break;
        case gl.FLOAT_MAT4:
          setters[name] = (value) => {
            gl.uniformMatrix4fv(location, false, new Float32Array(value));
            currentUniforms[name] = value;
          };
          break;
        default:
          setters[name] = () => {};
      }
    }
    return setters;
  };

  const enableDefaultDepthTest = (cache) => {
    const gl = cache.gl;
    const depthTest = cache.depthTest;
    if (!depthTest.enabled) {
      gl.enable(gl.DEPTH_TEST);
      depthTest.enabled = true;
    }
    // LESS = 0x0201 = 513
    gl.depthFunc(513);
    gl.depthMask(true);
    gl.depthRange(0, 1);
    depthTest.b = true;
    depthTest.toggle = cache.toggle;
  };

  const drawEntity = (cache, entityPtr) => {
    const entityPayload = readHandle(entityPtr);
    if (!entityPayload || entityPayload.tag !== TAG_WEBGL_ENTITY) return;

    const mesh = meshParts(entityPayload.mesh);
    if (!mesh || listLength(mesh.dataPtr) === 0) return;

    const gl = cache.gl;
    const vert = shaderParts(entityPayload.vert);
    const frag = shaderParts(entityPayload.frag);
    const vertId = assignShaderId(entityPayload.vert);
    const fragId = assignShaderId(entityPayload.frag);
    const progid = `${vertId}#${fragId}`;

    let program = cache.programs[progid];
    if (!program) {
      let vshader = cache.shaders[vertId];
      if (!vshader) {
        vshader = doCompile(gl, vert.src, gl.VERTEX_SHADER);
        cache.shaders[vertId] = vshader;
      }
      let fshader = cache.shaders[fragId];
      if (!fshader) {
        fshader = doCompile(gl, frag.src, gl.FRAGMENT_SHADER);
        cache.shaders[fragId] = fshader;
      }
      const glProgram = doLink(gl, vshader, fshader);
      const attrNames = [...new Set([...vert.attributes, ...frag.attributes])];
      const uniformNames = [...new Set([...vert.uniforms, ...frag.uniforms])];
      program = {
        glProgram,
        attributes: attrNames,
        uniformNames,
        currentUniforms: {},
        activeAttributes: [],
        activeAttributeLocations: [],
      };
      program.uniformSetters = createUniformSetters(gl, cache, program, uniformNames);
      const numActive = gl.getProgramParameter(glProgram, gl.ACTIVE_ATTRIBUTES);
      for (let i = 0; i < numActive; i++) {
        program.activeAttributes.push(gl.getActiveAttrib(glProgram, i));
        program.activeAttributeLocations.push(
          gl.getAttribLocation(glProgram, program.activeAttributes[i].name)
        );
      }
      cache.programs[progid] = program;
    }

    if (cache.lastProgId !== progid) {
      gl.useProgram(program.glProgram);
      cache.lastProgId = progid;
    }

    const values = uniformsByName(entityPayload.uniforms, program.uniformNames);
    for (const [name, setter] of Object.entries(program.uniformSetters)) {
      if (values[name] !== undefined) setter(values[name]);
    }

    // Buffer cache keyed by mesh handle object identity when possible.
    const meshKey = readHandle(entityPayload.mesh) || { __meshKey: entityPayload.mesh };
    let buffer = cache.buffers.get(meshKey);
    if (!buffer) {
      buffer = bindSetup(gl, mesh);
      cache.buffers.set(meshKey, buffer);
    }

    for (let i = 0; i < program.activeAttributes.length; i++) {
      const attribute = program.activeAttributes[i];
      const attribLocation = program.activeAttributeLocations[i];
      if (buffer.buffers[attribute.name] === undefined) {
        buffer.buffers[attribute.name] = bindAttribute(
          gl,
          attribute,
          mesh,
          program.attributes
        );
      }
      if (!buffer.buffers[attribute.name]) continue;
      gl.bindBuffer(gl.ARRAY_BUFFER, buffer.buffers[attribute.name]);
      const attributeInfo = getAttributeInfo(gl, attribute.type);
      if (!attributeInfo) continue;
      if (attributeInfo.arraySize === 1) {
        gl.enableVertexAttribArray(attribLocation);
        gl.vertexAttribPointer(
          attribLocation,
          attributeInfo.size,
          attributeInfo.baseType,
          false,
          0,
          0
        );
      } else {
        const offset = attributeInfo.size * 4;
        const stride = offset * attributeInfo.arraySize;
        for (let m = 0; m < attributeInfo.arraySize; m++) {
          gl.enableVertexAttribArray(attribLocation + m);
          gl.vertexAttribPointer(
            attribLocation + m,
            attributeInfo.size,
            attributeInfo.baseType,
            false,
            stride,
            offset * m
          );
        }
      }
    }

    cache.toggle = !cache.toggle;
    enableDefaultDepthTest(cache);

    if (buffer.indexBuffer) {
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, buffer.indexBuffer);
      gl.drawElements(mesh.mode, buffer.numIndices, gl.UNSIGNED_INT, 0);
    } else {
      gl.drawArrays(mesh.mode, 0, buffer.numIndices);
    }
  };

  const drawGL = (model, domNode) => {
    const cache = ensureCache(model);
    const gl = cache.gl;
    if (!gl) return domNode;

    gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
    if (!cache.depthTest.b) {
      gl.depthMask(true);
      cache.depthTest.b = true;
    }
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT | gl.STENCIL_BUFFER_BIT);

    for (const entityPtr of listItems(model.entities)) {
      try {
        drawEntity(cache, entityPtr);
      } catch (err) {
        if (typeof console !== "undefined") {
          console.warn("webgl drawEntity failed", err);
        }
      }
    }
    return domNode;
  };

  // customNodeHandlers.webgl: render(model, facts), diff(oldModel, newModel, domNode)
  const render = (model, facts) => {
    if (typeof document === "undefined") return null;
    if (!model) return null;

    const options = decodeOptions(model.options | 0);
    const canvas = document.createElement("canvas");
    applyFacts(canvas, facts);

    const gl =
      canvas.getContext &&
      (canvas.getContext("webgl", options.contextAttributes) ||
        canvas.getContext("experimental-webgl", options.contextAttributes) ||
        canvas.getContext("webgl2", options.contextAttributes));

    if (gl && typeof WeakMap !== "undefined") {
      for (const setting of options.sceneSettings) setting(gl);
      gl.getExtension("OES_standard_derivatives");
      gl.getExtension("OES_element_index_uint");

      const cache = ensureCache(model);
      cache.gl = gl;
      cache.STENCIL_WRITEMASK = gl.getParameter(gl.STENCIL_WRITEMASK);

      rAF(() => drawGL(model, canvas));
      return canvas;
    }

    const fallback = document.createElement("div");
    fallback.innerHTML =
      '<a href="https://get.webgl.org/">Enable WebGL</a> to see this content!';
    applyFacts(fallback, facts);
    return fallback;
  };

  const diff = (oldModel, newModel, domNode) => {
    if (oldModel?.cache && newModel) {
      newModel.cache = oldModel.cache;
    }
    return drawGL(newModel, domNode);
  };

  return {
    entity,
    toHtml,
    render,
    diff,
  };
}
