/*
import Result exposing (Ok)
import Maybe exposing (Just, Nothing)
*/

var wireRefs = (function () {
  var refs = new Map();
  var counter = 0; // uInt32 max
  var f = {}
  f.add = function(obj) {
    counter++;
    refs.set(counter, obj);
    return counter;
  }
  f.getFinal = function(k) {
    let v = refs.get(k);
    refs.delete(k);
    return v;
  }
  f.clear = function() {
    refs = new Map();
  };
  f.all = function() {
    return [refs.keys(), refs];
  }
  return f;
})();

var _LamderaCodecs_encodeWithRef = function(a) {
  return wireRefs.add(a);
}

var _LamderaCodecs_decodeWithRef = function(ref) {
  return wireRefs.getFinal(ref);
}

var _LamderaCodecs_encodeBytes = function(s) { return _Lamdera_Json_wrap(s); }

function _Lamdera_Json_wrap__DEBUG(value) { return { $: __0_JSON, a: value }; }
function _Lamdera_Json_wrap__PROD(value) { return value; }

function _LamderaCodecs_Json_decodePrim(decoder) {
  return { $: __1_PRIM, __decoder: decoder };
}

var _LamderaCodecs_decodeBytes = _Json_decodePrim(function(value) {
  return (typeof value === 'object' && value instanceof DataView)
    ? __Result_Ok(value)
    : _Json_expecting('a DataView', value) ;
    // : console.log('error: expecting DataView, got', value) ;
});

var _LamderaCodecs_debug = function(s) {
  console.log(s);
  return _Utils_Tuple0;
}

// Duplicate of _Bytes_decode that expects all bytes to be consumed,
// otherwise it fails to decode.
var _LamderaCodecs_bytesDecodeStrict = F2(function(decoder, bytes)
{
  try {
    var res = A2(decoder, bytes, 0);
    const w = bytes.byteLength;
    if (w !== res.a) {
      // For now just log issues, in future we'll actually fail on this case
      console.log(`❌ bytesDecodeStrict did not consume all bytes: length:${w}, consumed:${res.a}`, res.b, new Uint8Array(bytes.buffer));
    }
    return __Maybe_Just(res.b);
  } catch(e) {
    console.log('❌ bytesDecodeStrict unexpected error:', e);
    return __Maybe_Nothing;
  }
});
