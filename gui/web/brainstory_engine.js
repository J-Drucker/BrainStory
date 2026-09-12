(async () => {
  try {
    const response = await fetch(new URL('brainstory_web.wasm', document.baseURI));
    if (!response.ok) throw new Error(`Engine download failed: ${response.status}`);
    const { instance } = await WebAssembly.instantiate(await response.arrayBuffer(), {});
    const api = instance.exports;
    const encoder = new TextEncoder();
    const decoder = new TextDecoder();
    const worker = new Worker(new URL('brainstory_worker.js', document.baseURI));
    const pending = new Map();
    let nextId = 0;
    worker.onmessage = ({ data }) => {
      const job = pending.get(data.id);
      if (!job) return;
      pending.delete(data.id);
      if (data.error) job.reject(new Error(data.error));
      else job.resolve(data.response);
    };
    worker.onerror = (event) => {
      for (const job of pending.values()) job.reject(new Error(event.message));
      pending.clear();
    };
    globalThis.brainstoryEngineAsync = request => new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject });
      worker.postMessage({ id, request });
    });
    globalThis.brainstoryImportCnt = (bytes, filename) => new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject });
      const ownedBytes = bytes.slice();
      worker.postMessage(
        { id, cntBytes: ownedBytes, filename },
        [ownedBytes.buffer],
      );
    });
    globalThis.brainstoryEngine = (request) => {
      const bytes = encoder.encode(request);
      const input = api.allocate(bytes.length);
      let output;
      try {
        new Uint8Array(api.memory.buffer, input, bytes.length).set(bytes);
        output = api.run(input, bytes.length);
        const memory = new Uint8Array(api.memory.buffer);
        let end = output;
        while (memory[end] !== 0 && end < memory.length) end++;
        return decoder.decode(memory.subarray(output, end));
      } finally {
        api.release(input, bytes.length);
        if (output) api.release_result(output);
      }
    };
    const script = document.createElement('script');
    script.src = 'flutter_bootstrap.js';
    document.body.append(script);
  } catch (error) {
    document.body.textContent = `BrainStory could not load its processing engine. Reload to retry. ${error.message}`;
  }
})();
