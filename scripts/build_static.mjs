import { cp, mkdir, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, '..');
const outputDir = path.join(repoRoot, 'dist');

await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });

for (const entry of ['index.html', 'assets', 'staticwebapp.config.json']) {
  await cp(path.join(repoRoot, entry), path.join(outputDir, entry), { recursive: true });
}
