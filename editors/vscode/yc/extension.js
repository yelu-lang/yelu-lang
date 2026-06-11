// yc language client — launches the yelu-lsp server and connects it to
// .yc documents (formatting, diagnostics). Plain CommonJS, no build step.
//
// Server binary resolution:
//   1. the `yc.server.path` setting if non-empty;
//   2. else <first workspace folder>/_build/default/src/bin/yelu_lsp/yelu_lsp.exe
//      (so opening the yelu repo + `dune build` just works).

const { workspace, window } = require('vscode');
const { LanguageClient, TransportKind } = require('vscode-languageclient/node');
const fs = require('fs');
const path = require('path');

let client;

function resolveServer() {
  const configured = workspace.getConfiguration('yc').get('server.path');
  if (configured && configured.length > 0) return configured;
  const folders = workspace.workspaceFolders;
  if (folders && folders.length > 0) {
    return path.join(
      folders[0].uri.fsPath,
      '_build', 'default', 'src', 'bin', 'yelu_lsp', 'yelu_lsp.exe');
  }
  return null;
}

function activate(_context) {
  const server = resolveServer();
  if (!server || !fs.existsSync(server)) {
    window.showWarningMessage(
      `yc: language server not found${server ? ' at ' + server : ''}. ` +
      `Build it (\`dune build src/bin/yelu_lsp/\`) or set "yc.server.path".`);
    return;
  }
  const serverOptions = {
    run: { command: server, transport: TransportKind.stdio },
    debug: { command: server, transport: TransportKind.stdio },
  };
  const clientOptions = {
    documentSelector: [{ scheme: 'file', language: 'yc' }],
  };
  client = new LanguageClient('yc', 'Yelu-cmake LSP', serverOptions, clientOptions);
  client.start();
}

function deactivate() {
  return client ? client.stop() : undefined;
}

module.exports = { activate, deactivate };
