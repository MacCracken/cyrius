const { LanguageClient, TransportKind } = require("vscode-languageclient/node");
const path = require("path");
const fs = require("fs");

let client;

function findLsp() {
  // Check common locations for cyrius-lsp binary
  const home = process.env.HOME || "";
  const candidates = [
    path.join(process.env.CYRIUS_HOME || path.join(home, ".cyrius"), "bin/cyrius-lsp"),
    path.join(home, ".local/bin/cyrius-lsp"),
    "/usr/local/bin/cyrius-lsp",
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  return null;
}

function activate(context) {
  const lspPath = findLsp();
  if (!lspPath) {
    const vscode = require("vscode");
    vscode.window.showWarningMessage(
      "cyrius-lsp not found (looked in $CYRIUS_HOME/bin, ~/.local/bin, /usr/local/bin). The Cyrius toolchain installs it to ~/.cyrius/bin."
    );
    return;
  }

  const serverOptions = {
    command: lspPath,
    transport: TransportKind.stdio,
  };

  const clientOptions = {
    documentSelector: [{ scheme: "file", language: "cyrius" }],
  };

  client = new LanguageClient(
    "cyrius-lsp",
    "Cyrius Language Server",
    serverOptions,
    clientOptions
  );

  client.start();
}

function deactivate() {
  if (client) return client.stop();
}

module.exports = { activate, deactivate };
