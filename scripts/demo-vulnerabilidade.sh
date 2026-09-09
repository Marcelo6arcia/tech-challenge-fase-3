#!/usr/bin/env bash
# =============================================================================
# demo-vulnerabilidade.sh — insere ou remove uma vulnerabilidade proposital
# para demonstrar a porta de qualidade do pipeline DevSecOps.
#
#   ./scripts/demo-vulnerabilidade.sh inserir flag-service
#   ./scripts/demo-vulnerabilidade.sh remover flag-service
#
# Serviços Python  -> dependência com CVE CRITICAL (falha no job SCA)
# Serviços Go      -> comando de shell com entrada do usuário (falha no SAST)
# =============================================================================
set -euo pipefail

ACAO="${1:-}"
SERVICO="${2:-}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PYTHON_SERVICES="flag-service targeting-service analytics-service"
GO_SERVICES="auth-service evaluation-service"

MARCADOR="# === DEMO DE VULNERABILIDADE - REMOVER ANTES DO MERGE ==="
DEP_VULNERAVEL="PyYAML==5.3.1"
ARQUIVO_GO_DEMO="vuln_demo.go"

uso() {
  cat <<EOF
Uso: $0 <inserir|remover> <servico>

Serviços disponíveis:
  Python (demo de SCA):  ${PYTHON_SERVICES}
  Go     (demo de SAST): ${GO_SERVICES}

Exemplos:
  $0 inserir flag-service     # adiciona PyYAML 5.3.1 (CVE-2020-14343, CVSS 9.8)
  $0 remover flag-service
  $0 inserir auth-service     # adiciona exec.Command com entrada do usuario (gosec G204)
  $0 remover auth-service
EOF
  exit 1
}

[[ -z "$ACAO" || -z "$SERVICO" ]] && uso
[[ ! -d "$RAIZ/$SERVICO" ]] && { echo "Serviço '$SERVICO' não encontrado."; uso; }

e_python() { [[ " $PYTHON_SERVICES " == *" $SERVICO "* ]]; }
e_go()     { [[ " $GO_SERVICES "     == *" $SERVICO "* ]]; }

# -----------------------------------------------------------------------------
inserir_python() {
  local req="$RAIZ/$SERVICO/requirements.txt"

  if grep -q "$MARCADOR" "$req"; then
    echo "A vulnerabilidade já está presente em $SERVICO."
    return
  fi

  cat >> "$req" <<EOF

$MARCADOR
# CVE-2020-14343 (CVSS 9.8, CRITICAL): execucao arbitraria de codigo via
# yaml.full_load. Corrigida a partir da 5.4.
$DEP_VULNERAVEL
EOF

  echo "Dependência vulnerável adicionada em $SERVICO/requirements.txt"
  echo "O job SCA deve falhar com CVE-2020-14343."
}

remover_python() {
  local req="$RAIZ/$SERVICO/requirements.txt"

  python3 - "$req" "$MARCADOR" <<'PY'
import sys, pathlib
caminho, marcador = sys.argv[1], sys.argv[2]
p = pathlib.Path(caminho)
linhas = p.read_text().splitlines()
if marcador not in linhas:
    print("Nada a remover.")
    sys.exit(0)
corte = linhas.index(marcador)
# remove também a linha em branco imediatamente anterior ao marcador
while corte > 0 and linhas[corte - 1].strip() == "":
    corte -= 1
p.write_text("\n".join(linhas[:corte]) + "\n")
print("Dependência vulnerável removida.")
PY
}

# -----------------------------------------------------------------------------
inserir_go() {
  local arquivo="$RAIZ/$SERVICO/$ARQUIVO_GO_DEMO"

  if [[ -f "$arquivo" ]]; then
    echo "A vulnerabilidade já está presente em $SERVICO."
    return
  fi

  cat > "$arquivo" <<'EOF'
package main

// === DEMO DE VULNERABILIDADE - REMOVER ANTES DO MERGE ===
//
// gosec G204: Subprocess launched with a potential tainted input.
// O valor do parâmetro `host` vem direto da query string e é entregue ao shell:
// `?host=8.8.8.8;cat /etc/passwd` executaria o segundo comando.
//
// Este arquivo existe apenas para demonstrar a porta de qualidade de SAST.

import (
	"net/http"
	"os/exec"
)

func demoVulneravelHandler(w http.ResponseWriter, r *http.Request) {
	host := r.URL.Query().Get("host")

	saida, err := exec.Command("sh", "-c", "ping -c 1 "+host).Output()
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	_, _ = w.Write(saida)
}
EOF

  echo "Arquivo $SERVICO/$ARQUIVO_GO_DEMO criado."
  echo "O job SAST deve falhar com gosec G204."
}

remover_go() {
  local arquivo="$RAIZ/$SERVICO/$ARQUIVO_GO_DEMO"

  if [[ -f "$arquivo" ]]; then
    rm "$arquivo"
    echo "Arquivo de demonstração removido."
  else
    echo "Nada a remover."
  fi
}

# -----------------------------------------------------------------------------
case "$ACAO" in
  inserir)
    if e_python; then inserir_python
    elif e_go;   then inserir_go
    else uso; fi
    ;;
  remover)
    if e_python; then remover_python
    elif e_go;   then remover_go
    else uso; fi
    ;;
  *)
    uso
    ;;
esac

echo
echo "Diferença gerada:"
git -C "$RAIZ" --no-pager diff --stat -- "$SERVICO" || true
