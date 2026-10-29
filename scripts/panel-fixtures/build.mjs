// Bundle gen.ts with esbuild (from SR-Jkai-Core's node_modules). `@core/` is
// Core's src/lib, `@main/` is Main's, and each repo's own `$lib/` imports
// resolve inside that repo.
import path from 'node:path';
import { access } from 'node:fs/promises';

const [core, main, outfile] = process.argv.slice(2);
const { build } = await import(path.join(core, 'node_modules/esbuild/lib/main.js'));
const here = path.dirname(new URL(import.meta.url).pathname);
const libOf = { core: path.join(core, 'src/lib'), main: path.join(main, 'src/lib') };

async function file(base) {
  for (const ext of ['.ts', '.js', '/index.ts']) {
    try { await access(base + ext); return base + ext; } catch {}
  }
  return base;
}

await build({
  entryPoints: [path.join(here, 'gen.ts')],
  bundle: true,
  platform: 'node',
  format: 'esm',
  outfile,
  nodePaths: [path.join(core, 'node_modules')],
  logLevel: 'warning',
  plugins: [{
    name: 'lib-aliases',
    setup(b) {
      b.onResolve({ filter: /^@(core|main)\// }, async (args) => {
        const [, repo, rest] = args.path.match(/^@(core|main)\/(.*)$/);
        return { path: await file(path.join(libOf[repo], rest)) };
      });
      b.onResolve({ filter: /^\$lib\// }, async (args) => {
        const lib = args.importer.startsWith(libOf.core) ? libOf.core : libOf.main;
        return { path: await file(path.join(lib, args.path.slice('$lib/'.length))) };
      });
    },
  }],
});
