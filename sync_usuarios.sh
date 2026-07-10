#!/bin/bash
# ==========================================
#   NETSIMON 5.0 - SINCRONIZAÇÃO DE USUÁRIOS
#   /root/usuarios.db  →  /etc/painel/usuarios.db
# ==========================================
# CONTEXTO: o módulo do painel web (Dragon Core / dragonmodule,
# instalado separadamente e responsável por criar/remover usuários
# quando o cliente é cadastrado direto no painel) só grava DOIS
# campos em /root/usuarios.db: "login limite". Ele NUNCA escreve
# UUID, validade ou senha nesse arquivo — esses dados existem, mas
# ficam espalhados em outros lugares:
#
#   UUID     -> config.json do Xray (.inbounds[].settings.clients[],
#               casado pelo campo "email" == login)
#   validade -> conta Linux (chage -l login / useradd -e)
#   senha    -> /etc/SSHPlus/senha/login (texto puro, gravado pelo
#               próprio módulo — por isso este script GARANTE que
#               essa pasta existe, senão o módulo falha ao salvar)
#
# Este script NUNCA inventa UUID, senha ou validade novos para um
# usuário que já existe — ele apenas VAI BUSCAR o dado correto na
# fonte real acima. Isso elimina o bug histórico de UUID/validade
# sendo trocados a cada sincronização.
#
# Usuários criados localmente por adduser.sh/addtest.sh/xray.sh (que
# escrevem direto em /etc/painel/usuarios.db, sem passar por
# /root/usuarios.db) NUNCA são tocados ou removidos por este script,
# graças ao arquivo de rastreio .dragon_managed_logins: só entra
# nessa lista (e só pode ser removido por este script) quem já veio
# de /root/usuarios.db em algum momento — ou seja, quem foi criado
# pelo módulo do painel web, não pelo Netsimon diretamente.
# ==========================================

exec 200>/tmp/sync_usuarios.lock
flock -n 200 || exit 0

SOURCE="/root/usuarios.db"
TARGET="/etc/painel/usuarios.db"
TRACKED="/etc/painel/.dragon_managed_logins"

[ ! -f "$SOURCE" ] && touch "$SOURCE"
[ ! -f "$TARGET" ] && touch "$TARGET"
[ ! -f "$TRACKED" ] && touch "$TRACKED"

# Sem esta pasta, o módulo Dragon perde a senha do usuário
# silenciosamente (echo para um diretório inexistente).
mkdir -p /etc/SSHPlus/senha

cp "$TARGET" "$TARGET.bak" 2>/dev/null

resolve_uuid() {
    local login="$1"
    for cfg in /usr/local/etc/xray/config.json /etc/xray/config.json /etc/v2ray/config.json; do
        [ -f "$cfg" ] || continue
        local found
        found=$(jq -r --arg email "$login" \
            '.inbounds[]?.settings.clients[]? | select(.email==$email) | .id' \
            "$cfg" 2>/dev/null | head -n1)
        if [ -n "$found" ]; then
            echo "$found"
            return
        fi
    done
    echo ""
}

resolve_expira() {
    local login="$1"
    local raw
    raw=$(chage -l "$login" 2>/dev/null | grep "Account expires" | awk -F ': ' '{print $2}')
    if [ -n "$raw" ] && [ "$raw" != "never" ]; then
        date -d "$raw" '+%Y-%m-%d %H:%M:%S' 2>/dev/null
    fi
}

resolve_senha() {
    cat "/etc/SSHPlus/senha/$1" 2>/dev/null
}

TEMP_NEW=$(mktemp)
TEMP_TRACKED=$(mktemp)

while read -r login limite; do
    [ -z "$login" ] && continue

    uuid=$(resolve_uuid "$login")
    expira=$(resolve_expira "$login")
    senha=$(resolve_senha "$login")

    grep -v "^$login|" "$TARGET" > "$TARGET.tmp" 2>/dev/null
    mv "$TARGET.tmp" "$TARGET"

    echo "$login|$uuid|$expira|$senha|$limite" >> "$TEMP_NEW"
    echo "$login" >> "$TEMP_TRACKED"
done < "$SOURCE"

cat "$TEMP_NEW" >> "$TARGET"

# Remove do painel apenas quem já foi sincronizado por este script
# antes e sumiu de /root/usuarios.db (removido via módulo Dragon).
# Nunca mexe em login que não está no arquivo de rastreio — esses
# pertencem a outro fluxo de criação (adduser.sh/addtest.sh/xray.sh).
while read -r old_login; do
    [ -z "$old_login" ] && continue
    if ! grep -q "^$old_login " "$SOURCE" 2>/dev/null; then
        sed -i "/^$old_login|/d" "$TARGET"
    fi
done < "$TRACKED"

sort -u "$TEMP_TRACKED" -o "$TRACKED"
rm -f "$TEMP_NEW" "$TEMP_TRACKED"
