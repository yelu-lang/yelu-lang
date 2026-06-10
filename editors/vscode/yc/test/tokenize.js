// Headless TextMate verification for the yc grammar.
//
// Loads syntaxes/yc.tmLanguage.json with the real VS Code TextMate +
// Oniguruma engine and tokenizes a sample .yc file, printing a scope
// histogram. This is the same engine VS Code uses, so a clean run here
// means the highlighting is correct in the editor.
//
//   cd editors/vscode/yc/test
//   npm install            # vscode-textmate + vscode-oniguruma (devDeps)
//   node tokenize.js [path/to/sample.yc]
//
// Exits non-zero if the grammar fails to load.

const fs = require('fs');
const path = require('path');
const oniguruma = require('vscode-oniguruma');
const vsctm = require('vscode-textmate');

const HERE = __dirname;
const GRAMMAR = path.join(HERE, '..', 'syntaxes', 'yc.tmLanguage.json');
const SAMPLE = process.argv[2] ||
  path.join(HERE, '..', '..', '..', '..', 'probes', 'fmt', 'main.yc');

const wasmBin = fs.readFileSync(
  path.join(path.dirname(require.resolve('vscode-oniguruma')), 'onig.wasm')).buffer;
const onigLib = oniguruma.loadWASM(wasmBin).then(() => ({
  createOnigScanner: (p) => new oniguruma.OnigScanner(p),
  createOnigString: (s) => new oniguruma.OnigString(s),
}));

const registry = new vsctm.Registry({
  onigLib,
  loadGrammar: (scope) => scope === 'source.yc'
    ? vsctm.parseRawGrammar(fs.readFileSync(GRAMMAR, 'utf8'), GRAMMAR)
    : null,
});

registry.loadGrammar('source.yc').then((grammar) => {
  if (!grammar) { console.error('FAILED to load source.yc grammar'); process.exit(2); }
  const lines = fs.readFileSync(SAMPLE, 'utf8').split('\n');
  let stack = vsctm.INITIAL;
  const seen = {};
  lines.forEach((line) => {
    const r = grammar.tokenizeLine(line, stack);
    for (const t of r.tokens) {
      const txt = line.substring(t.startIndex, t.endIndex);
      const top = t.scopes[t.scopes.length - 1];
      if (top !== 'source.yc' && txt.trim() !== '') seen[top] = (seen[top] || 0) + 1;
    }
    stack = r.ruleStack;
  });
  console.log(`scope histogram for ${path.relative(process.cwd(), SAMPLE)}:`);
  Object.keys(seen).sort().forEach((k) => console.log(String(seen[k]).padStart(5), k));
});
