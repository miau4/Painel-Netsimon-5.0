#!/bin/bash
# ==========================================
#   NETSIMON 5.0 - USUÁRIOS ONLINE
#   SSH / WebSocket / Xray VLESS
# ==========================================
# Este arquivo funciona em dois modos:
#   1) Executado diretamente (bash online.sh): mostra a tela
#      interativa de "Usuários Conectados Agora".
#   2) "Sourced" por outro script (menu.sh, xray.sh): expõe as
#      funções netsimon_online_count() / netsimon_online_count_xray()
#      / netsimon_online_count_ssh(), usadas para os contadores de
#      "Online" no cabeçalho do menu principal, no submenu de
#      usuários e no Xray Manager — SEMPRE com o mesmo resultado,
#      porque é a mesma função calculando em todos os lugares (fonte
#      única de verdade, sem duas contagens divergentes).

USERDB="${USERDB:-/etc/painel/usuarios.db}"
XRAY_LOG="${XRAY_LOG:-/var/log/xray/access.log}"

# ── Linhas formatadas de sessões SSH/WebSocket ativas ─────────────
# Considera apenas logins que existem no usuarios.db (evita contar
# sessões SSH de administração, ex.: o próprio root gerenciando o
# painel, como se fossem clientes do serviço).
_netsimon_online_ssh_rows() {
    [ ! -s "$USERDB" ] && return
    while read -r user; do
        [[ -z "$user" ]] && continue
        grep -q "^$user|" "$USERDB" 2>/dev/null || continue

        local ip_conn dur dur_str mins
        ip_conn=$(ss -tnp 2>/dev/null | awk -v u="sshd" '$NF ~ u' | grep ESTAB | \
            awk '{print $5}' | cut -d: -f1 | grep -v "127.0.0.1" | head -n1)
        [[ -z "$ip_conn" ]] && ip_conn="WebSocket"

        dur=$(ps -u "$user" -o etimes= 2>/dev/null | sort -n | head -n1)
        if [ -n "$dur" ]; then
            mins=$(( dur / 60 ))
            dur_str="${mins}min"
        else
            dur_str="--"
        fi

        printf "%s\x1f%s\x1f%s\x1f%s\n" "$user" "$ip_conn" "SSH/WS" "$dur_str"
    done < <(who 2>/dev/null | awk '{print $1}' | sort -u)
}

# ── Linhas formatadas de sessões Xray/VLESS ativas (últimos 90s) ──
_netsimon_online_xray_rows() {
    [ ! -f "$XRAY_LOG" ] || [ ! -s "$USERDB" ] && return
    local now recent
    now=$(date +%s)
    recent=$(tail -n 200 "$XRAY_LOG" 2>/dev/null | grep "accepted")

    while IFS='|' read -r user uuid exp pass lim; do
        [[ -z "$user" ]] && continue
        local line ts ts_epoch diff ip_x
        line=$(echo "$recent" | grep "email: $user" | tail -n1)
        [[ -z "$line" ]] && continue

        ts=$(echo "$line" | awk '{print $1 " " $2}')
        ts_epoch=$(date -d "$ts" +%s 2>/dev/null || echo 0)
        diff=$(( now - ts_epoch ))
        [ "$diff" -gt 90 ] && continue

        ip_x=$(echo "$line" | awk '{print $3}' | cut -d: -f1)
        [[ -z "$ip_x" || "$ip_x" == "127.0.0.1" ]] && ip_x="tunnel"

        printf "%s\x1f%s\x1f%s\x1f%s\n" "$user" "$ip_x" "XRAY/VLESS" "--"
    done < "$USERDB"
}

# ── Contadores (fonte única usada em todo o painel) ────────────────
netsimon_online_count_ssh()  { _netsimon_online_ssh_rows  | sort -u | wc -l; }
netsimon_online_count_xray() { _netsimon_online_xray_rows | sort -u | wc -l; }
netsimon_online_count() {
    { _netsimon_online_ssh_rows; _netsimon_online_xray_rows; } | sort -u | wc -l
}

# ── Tela interativa ──────────────────────────────────────────────
_netsimon_online_screen() {
    P=$'\033[1;35m'; G=$'\033[1;32m'; R=$'\033[1;31m'; Y=$'\033[1;33m'
    W=$'\033[1;37m'; C=$'\033[1;36m'; NC=$'\033[0m'

    clear
    echo -e "${P}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${P}║${W}                👥 USUÁRIOS CONECTADOS AGORA                  ${P}║${NC}"
    echo -e "${P}╚══════════════════════════════════════════════════════════════╝${NC}"
    printf " ${W}%-15s | %-20s | %-12s | %-6s${NC}\n" "USUÁRIO" "IP DE CONEXÃO" "PROTOCOLO" "DURAÇÃO"
    echo -e "${P}────────────────────────────────────────────────────────────────${NC}"

    local rows
    rows=$( { _netsimon_online_ssh_rows; _netsimon_online_xray_rows; } | sort -u )

    if [ -n "$rows" ]; then
        while IFS=$'\x1f' read -r ru rip rproto rdur; do
            [ -z "$ru" ] && continue
            printf " ${G}%-15s${NC} | ${C}%-20s${NC} | ${Y}%-12s${NC} | ${W}%-6s${NC}\n" \
                "$ru" "$rip" "$rproto" "$rdur"
        done <<< "$rows"
    else
        echo -e "             ${R}Nenhum usuário logado no momento.${NC}"
    fi

    echo -e "${P}────────────────────────────────────────────────────────────────${NC}"
    local total
    if [ -z "$rows" ]; then
        total=0
    else
        total=$(echo "$rows" | grep -c '.')
    fi
    echo -e " ${W}TOTAL DE CONEXÕES: ${G}$total${NC}"
    echo -e "${P}────────────────────────────────────────────────────────────────${NC}"
    read -p " Pressione ENTER para voltar..."
}

# Só roda a tela se o arquivo foi chamado diretamente (bash online.sh),
# nunca quando é "sourced" por outro script.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _netsimon_online_screen
fi
