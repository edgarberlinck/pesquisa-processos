#!/bin/bash
set -e

NAME="pesquisa-processos"
REPO="edgarberlinck/$NAME"
INSTALL_BASE="/usr/local/bin/$NAME"
ENV_FILE="$HOME/.${NAME}.env"

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

# 🔍 Detecta sistema operacional e arquitetura
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)
PLATFORM=""
EXT=""

case "$OS" in
  linux)
    PLATFORM="linux-x64"
    EXT=""
    ;;
  darwin)
    if [[ "$ARCH" == "arm64" ]]; then
      PLATFORM="macos"
    else
      PLATFORM="macos-x64"
    fi
    EXT=""
    ;;
  mingw*|msys*|windows_nt)
    PLATFORM="win-x64"
    EXT=".exe"
    ;;
  *)
    echo "❌ Plataforma não suportada: $OS"
    exit 1
    ;;
esac

echo "🧭 Plataforma detectada: $PLATFORM"

# 🔥 Obtém a última versão via GitHub API
LATEST=$(curl -s "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\1/')
if [ -z "$LATEST" ]; then
  echo "❌ Não foi possível obter a versão mais recente via GitHub API."
  exit 1
fi
echo "🆕 Última versão detectada: $LATEST"

# 📦 Verifica se já está instalado
CURRENT_VER=""
if [ -f "$ENV_FILE" ]; then
  CURRENT_BIN=$(grep "^alias $NAME=" "$ENV_FILE" | cut -d"'" -f2)
  if [ -x "$CURRENT_BIN" ]; then
    CURRENT_VER=$("$CURRENT_BIN" --version | sed 's/^v//')
    echo "📌 Versão atual instalada: $CURRENT_VER"
  fi
fi

if [ "$CURRENT_VER" = "$LATEST" ]; then
  echo "✅ Já está na última versão."
  exit 0
fi

# 📥 Monta URL e tenta download
FALLBACK_USED="no"
FILE_NAME="${NAME}-${PLATFORM}-${LATEST}${EXT}"
DL_URL="https://github.com/$REPO/releases/download/v$LATEST/$FILE_NAME"

echo "⬇️ Tentando baixar $FILE_NAME..."
curl -fL "$DL_URL" -o "$TMP_DIR/$FILE_NAME" || {
  # Se falhou e estamos em macOS ARM, tenta fallback para macos-x64
  if [[ "$PLATFORM" = "macos" ]]; then
    echo "⚠️ Binário nativo para macOS ARM não encontrado. Tentando fallback para macos-x64..."
    PLATFORM="macos-x64"
    FILE_NAME="${NAME}-${PLATFORM}-${LATEST}${EXT}"
    DL_URL="https://github.com/$REPO/releases/download/v$LATEST/$FILE_NAME"
    curl -fL "$DL_URL" -o "$TMP_DIR/$FILE_NAME" || {
      echo "❌ Nenhum binário compatível encontrado. Abortando."
      exit 1
    }
    FALLBACK_USED="yes"
  else
    echo "❌ Erro ao baixar binário: $DL_URL"
    exit 1
  fi
}

# 🧪 Verifica se é realmente um binário
echo "🔍 Verificando arquivo baixado..."
FILE_TYPE=$(file "$TMP_DIR/$FILE_NAME")
echo "🧾 Tipo detectado: $FILE_TYPE"

if echo "$FILE_TYPE" | grep -qE 'HTML|ASCII text'; then
  echo "❌ O arquivo baixado não é um binário válido. Verifique o nome do asset."
  exit 1
fi

# 🚚 Instalação
DEST_DIR="$INSTALL_BASE/$LATEST"
mkdir -p "$DEST_DIR"
DEST_BIN="$DEST_DIR/$NAME"

mv "$TMP_DIR/$FILE_NAME" "$DEST_BIN"
chmod +x "$DEST_BIN"

# 🔗 Cria alias
echo "alias $NAME='$DEST_BIN'" > "$ENV_FILE"
echo "🔄 Alias atualizado em $ENV_FILE"

# ➕ Garante source no shell RC
RC_FILE="$HOME/.bashrc"
[ -n "$ZSH_VERSION" ] && RC_FILE="$HOME/.zshrc"
[ -f "$HOME/.zshrc" ] && RC_FILE="$HOME/.zshrc"

if ! grep -qF "$ENV_FILE" "$RC_FILE"; then
  printf "\nsource \"%s\"\n" "$ENV_FILE" >> "$RC_FILE"
  echo "🔁 $RC_FILE atualizado para carregar o alias"
else
  echo "✅ $RC_FILE já carrega o alias"
fi

echo "🎉 Instalação da versão $LATEST concluída!"
[ "$FALLBACK_USED" = "yes" ] && echo "⚠️ Atenção: usando binário Intel (x64) via Rosetta."
echo "👉 Rode 'source $ENV_FILE' ou abra um novo terminal para começar a usar."
