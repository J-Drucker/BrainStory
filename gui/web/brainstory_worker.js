let engine;
let cntModulePromise;
const ready = fetch('brainstory_web.wasm')
  .then(response => { if (!response.ok) throw new Error('Engine download failed'); return response.arrayBuffer(); })
  .then(bytes => WebAssembly.instantiate(bytes, {}))
  .then(result => { engine = result.instance.exports; });
self.onmessage = async ({ data: { id, request, cntBytes, filename } }) => {
  let input;
  let output;
  let bytes;
  try {
    if (cntBytes) {
      const payload = await importCnt(cntBytes, filename || 'recording.cnt');
      self.postMessage({ id, response: JSON.stringify(payload) });
      return;
    }
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

async function cntModule() {
  if (!cntModulePromise) {
    importScripts('brainstory_cnt.js');
    cntModulePromise = createBrainStoryCntModule({
      locateFile: path => new URL(path, self.location.href).href,
    });
  }
  return cntModulePromise;
}

async function importCnt(bytes, filename) {
  const module = await cntModule();
  const safeName = filename.replace(/[^A-Za-z0-9._-]/g, '_');
  const path = `/tmp/${Date.now()}-${safeName}`;
  module.FS.writeFile(path, bytes);
  let samplePointer = 0;
  let extensionPointer = 0;
  try {
    const pathLength = module.lengthBytesUTF8(path) + 1;
    const pathPointer = module._malloc(pathLength);
    try {
      module.stringToUTF8(path, pathPointer, pathLength);
      if (!module._bs_cnt_open(pathPointer)) {
        throw new Error('libeep could not read this ANT CNT file.');
      }
    } finally {
      module._free(pathPointer);
    }

    const channelCount = module._bs_cnt_channel_count();
    const sampleCount = Number(module._bs_cnt_sample_count());
    const sampleRate = module._bs_cnt_sample_rate();
    if (channelCount <= 0 || sampleCount <= 0 || sampleRate <= 0) {
      throw new Error('The CNT file contains no usable signal data.');
    }
    const channelLabels = Array.from({ length: channelCount }, (_, index) =>
      module.UTF8ToString(module._bs_cnt_channel_label(index)) || `Ch ${index + 1}`,
    );

    const interleavedPointer = module._bs_cnt_samples();
    const interleaved = new Float32Array(
      module.HEAPF32.buffer,
      interleavedPointer,
      channelCount * sampleCount,
    );
    const channelMajor = new Float32Array(channelCount * sampleCount);
    for (let sample = 0; sample < sampleCount; sample++) {
      for (let channel = 0; channel < channelCount; channel++) {
        channelMajor[channel * sampleCount + sample] =
          interleaved[sample * channelCount + channel];
      }
    }

    samplePointer = module._malloc(8);
    extensionPointer = module._malloc(40);
    const markers = [];
    const impedanceTimes = [];
    const impedanceRows = channelLabels.map(() => []);
    const triggerCount = module._bs_cnt_trigger_count();
    for (let index = 0; index < triggerCount; index++) {
      module.HEAPU8.fill(0, samplePointer, samplePointer + 8);
      module.HEAPU8.fill(0, extensionPointer, extensionPointer + 40);
      const labelPointer = module._bs_cnt_trigger(
        index,
        samplePointer,
        extensionPointer,
      );
      if (!labelPointer) continue;
      const data = new DataView(module.HEAPU8.buffer);
      const sample = Number(data.getBigUint64(samplePointer, true));
      const triggerType = data.getInt32(extensionPointer, true);
      const code = data.getInt32(extensionPointer + 4, true);
      const durationSamples = Number(
        data.getBigUint64(extensionPointer + 8, true),
      );
      const text = offset => {
        const pointer = data.getUint32(extensionPointer + offset, true);
        return pointer ? module.UTF8ToString(pointer) : '';
      };
      const label = module.UTF8ToString(labelPointer);
      const condition = text(16);
      const description = text(20);
      const impedances = text(28);
      const onsetMicros = Math.round(sample * 1000000 / sampleRate);
      const durationMicros = Math.round(durationSamples * 1000000 / sampleRate);
      if (description.toLowerCase() === 'impedance' && impedances) {
        impedanceTimes.push(onsetMicros);
        const values = impedances.trim().split(/\s+/).map(Number);
        impedanceRows.forEach((row, channel) =>
          row.push(Number.isFinite(values[channel]) ? values[channel] : null),
        );
        continue;
      }
      const lower = `${label} ${description}`.toLowerCase();
      markers.push({
        label,
        onsetMicros,
        durationMicros,
        markerType: lower.includes('bad') || lower.includes('artifact')
          ? 'artifact'
          : durationMicros === 0 ? 'event' : 'window',
        attributes: {
          source: 'ANT CNT',
          'ant.triggerType': triggerType,
          'ant.triggerCode': code,
          ...(condition ? { 'ant.condition': condition } : {}),
          ...(description ? { 'ant.description': description } : {}),
        },
      });
    }

    return {
      ok: true,
      payload: {
        sourceDescription: filename,
        sampleRate,
        channelLabels,
        channelCount,
        sampleCount,
        samplesBase64: bytesToBase64(new Uint8Array(channelMajor.buffer)),
        markers,
        impedance: impedanceTimes.length ? {
          channelLabels,
          measurementTimesMicros: impedanceTimes,
          ohmsByChannel: impedanceRows,
        } : null,
      },
    };
  } finally {
    if (samplePointer) module._free(samplePointer);
    if (extensionPointer) module._free(extensionPointer);
    module._bs_cnt_close();
    try { module.FS.unlink(path); } catch (_) {}
  }
}

function bytesToBase64(bytes) {
  const chunkSize = 0x8000;
  let binary = '';
  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }
  return btoa(binary);
}
