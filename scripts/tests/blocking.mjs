// Compile the bundled upstream code, without a browser, using a local-only fetch adapter.
import fs from 'node:fs/promises';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
globalThis.self = globalThis;
const originalFetch = globalThis.fetch;
globalThis.fetch = async url => {
  const parsed = new URL(url);
  if (parsed.protocol !== 'file:') throw new Error('Network is forbidden in compiler tests');
  return new Response(await fs.readFile(fileURLToPath(parsed)));
};
try {
  const { build } = await import('../../shared/blocking/compiler.mjs');
  const text = '||ads.example^$third-party\n@@||ads.example/allowed.js$script\nnews.test##.mica-test-ad\nnews.test##+js(set-constant, micaTest, true)';
  const output = await build([{name:'fixture',text,trustedSource:false}]);
  assert(output.windows.some(r=>r.host==='ads.example'&&r.action.type==='block'));
  assert(output.windows.some(r=>r.host==='ads.example'&&r.action.type==='ignore-previous-rules'));
  assert(output.cosmetic.some(r=>r.action.selector?.includes('.mica-test-ad')));
  assert(output.main.includes('micaTest') || output.isolated.includes('micaTest'));
  const off = await build([{name:'fixture',text}], {exceptions:['news.test']});
  assert(off.network.at(-1).trigger['if-domain'].includes('*news.test'));
  assert(off.main.includes('news.test') || off.isolated.includes('news.test'));
  await fs.mkdir(new URL('../../shared/fixtures/blocking/',import.meta.url),{recursive:true});
  const target = new URL('../../shared/fixtures/blocking/compiled.json',import.meta.url);
  if(process.env.MICA_WRITE_BLOCKING==='1') await fs.writeFile(target,JSON.stringify({windows:output.windows,cosmetic:output.cosmetic},null,2)+'\n');
  const fixture=JSON.parse(await fs.readFile(target,'utf8'));
  assert.deepEqual(output.windows,fixture.windows);
  assert.deepEqual(output.cosmetic,fixture.cosmetic);
  console.log('Bundled uBO compiler: network, allow, CSS, scriptlets and exceptions passed');
} finally {globalThis.fetch = originalFetch;}
