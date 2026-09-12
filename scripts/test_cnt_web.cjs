const assert = require('assert');
const fs = require('fs');
const path = require('path');

const createModule = require('../gui/web/brainstory_cnt.js');

async function main() {
  const module = await createModule({
    locateFile: name => path.resolve(__dirname, '../gui/web', name),
  });
  const cntPath = '/tmp/ant_minimal.cnt';
  module.FS.writeFile(
    cntPath,
    fs.readFileSync(path.resolve(__dirname, '../gui/test/fixtures/ant_minimal.cnt')),
  );
  const pathLength = module.lengthBytesUTF8(cntPath) + 1;
  const pathPointer = module._malloc(pathLength);
  module.stringToUTF8(cntPath, pathPointer, pathLength);
  assert.equal(module._bs_cnt_open(pathPointer), 1);
  module._free(pathPointer);

  try {
    assert.equal(module._bs_cnt_channel_count(), 2);
    assert.equal(Number(module._bs_cnt_sample_count()), 4);
    assert.equal(module._bs_cnt_sample_rate(), 100);
    assert.deepEqual(
      [0, 1].map(index =>
        module.UTF8ToString(module._bs_cnt_channel_label(index)),
      ),
      ['Fp1', 'Fp2'],
    );
    const samplePointer = module._bs_cnt_samples();
    assert.deepEqual(
      Array.from(
        new Float32Array(module.HEAPF32.buffer, samplePointer, 8),
      ),
      [1, 10, 2, 20, 3, 30, 4, 40],
    );

    const triggerSamplePointer = module._malloc(8);
    const extensionPointer = module._malloc(40);
    try {
      assert.equal(module._bs_cnt_trigger_count(), 1);
      assert.equal(
        module.UTF8ToString(
          module._bs_cnt_trigger(
            0,
            triggerSamplePointer,
            extensionPointer,
          ),
        ),
        '7',
      );
      assert.equal(
        Number(
          new DataView(module.HEAPU8.buffer).getBigUint64(
            triggerSamplePointer,
            true,
          ),
        ),
        2,
      );
    } finally {
      module._free(triggerSamplePointer);
      module._free(extensionPointer);
    }
  } finally {
    module._bs_cnt_close();
    module.FS.unlink(cntPath);
  }
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
