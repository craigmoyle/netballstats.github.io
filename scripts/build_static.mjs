import { createHash } from 'node:crypto';
import { cp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');
const outputDir = path.join(repoRoot, 'dist');
const assetSourceDir = path.join(repoRoot, 'assets');
const assetOutputDir = path.join(outputDir, 'assets');

const staticEntries = ['changelog', 'home-edge', 'index.html', 'compare', 'nwar', 'player', 'players', 'query', 'round', 'staticwebapp.config.json'];
const htmlEntries = ['changelog/index.html', 'home-edge/index.html', 'index.html', 'compare/index.html', 'nwar/index.html', 'player/index.html', 'players/index.html', 'query/index.html', 'round/index.html'];
const fingerprintedAssets = [
  'app.js',
  'charts.js',
  'compare.js',
  'config.js',
  'home-edge.js',
  'nwar.js',
  'player.js',
  'players.js',
  'query.js',
  'round.js',
  'styles.css',
  'telemetry.js',
  'theme.js'
];

const hashContent = (content) => createHash('sha256').update(content).digest('hex').slice(0, 10);
const fingerprintName = (assetName, content) => {
  const parsed = path.parse(assetName);
  return `${parsed.name}.${hashContent(content)}${parsed.ext}`;
};

await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });
await mkdir(assetOutputDir, { recursive: true });

for (const entry of staticEntries) {
  await cp(path.join(repoRoot, entry), path.join(outputDir, entry), { recursive: true });
}

await rm(assetOutputDir, { recursive: true, force: true });
await mkdir(assetOutputDir, { recursive: true });
await cp(path.join(assetSourceDir, 'fonts'), path.join(assetOutputDir, 'fonts'), { recursive: true });

const assetContents = new Map();
for (const assetName of fingerprintedAssets) {
  assetContents.set(assetName, await readFile(path.join(assetSourceDir, assetName)));
}

const assetManifest = new Map();
for (const assetName of fingerprintedAssets) {
  const content = assetContents.get(assetName);
  const outputName = fingerprintName(assetName, content);
  assetManifest.set(`/assets/${assetName}`, `/assets/${outputName}`);
  assetManifest.set(`assets/${assetName}`, `assets/${outputName}`);
  await writeFile(path.join(assetOutputDir, outputName), content);
}

for (const htmlEntry of htmlEntries) {
  const htmlPath = path.join(outputDir, htmlEntry);
  let html = await readFile(htmlPath, 'utf8');

  for (const [originalRef, fingerprintedRef] of assetManifest.entries()) {
    html = html.split(originalRef).join(fingerprintedRef);
  }

  await writeFile(htmlPath, html, 'utf8');
}
