let engine;
const ready = fetch('brainstory_web.wasm')
  .then(response => { if (!response.ok) throw new Error('Engine download failed'); return response.arrayBuffer(); })
  .then(bytes => WebAssembly.instantiate(bytes, {}))
  .then(result => { engine = result.instance.exports; });
self.onmessage = async ({ data: { id, request } }) => {
  let input;
  let output;
  let bytes;
  try {
    await ready;
    bytes = new TextEncoder().encode(request);
    input = engine.allocate(bytes.length);
    new Uint8Array(engine.memory.buffer, input, bytes.length).set(bytes);
    output = engine.run(input, bytes.length);
    const memory = new Uint8Array(engine.memory.buffer);
    let end = output;
    while (end < memory.length && memory[end] !== 0) end++;
    self.postMessage({ id, response: new TextDecoder().decode(memory.subarray(output, end)) });
  } catch (error) {
    self.postMessage({ id, error: error.message });
  } finally {
    if (input) engine.release(input, bytes.length);
    if (output) engine.release_result(output);
  }
};
