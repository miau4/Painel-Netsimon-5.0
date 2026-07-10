#!/bin/bash
# ==========================================
#   NETSIMON 5.0 - AUTO-RECOVERY NO BOOT
# ==========================================

BASE="/etc/painel"
XRAY_CONF="/usr/local/etc/xray/config.json"
XRAY_LOG="/var/log/xray/access.log"

# Aguarda rede e serviços estabilizarem
sleep 15

# Garante que a pasta que o módulo do painel web precisa pra salvar
# senha exista sempre, mesmo depois de uma reinstalação do módulo.
mkdir -p /etc/SSHPlus/senha

# 1. Limiter
if ! pgrep -f "limit.sh" > /dev/null; then
    screen -dmS limitador bash "$BASE/limit.sh"
fi

# 2. Xray
if [ -f "/usr/local/bin/xray" ] && [ -f "$XRAY_CONF" ]; then
    if ! systemctl is-active --quiet xray; then
        systemctl start xray
    fi
fi

# 3. WebSocket (proxy.py) — as duas portas são checadas e recuperadas
#    de forma independente uma da outra.
if ! ss -tln 2>/dev/null | grep -q ":80 "; then
    screen -dmS ws80 python3 "$BASE/proxy.py" 80 &>/dev/null
fi
if ! ss -tln 2>/dev/null | grep -q ":8080 "; then
    screen -dmS ws8080 python3 "$BASE/proxy.py" 8080 &>/dev/null
fi

# 4. CheckUser API
if ! pgrep -f "checkuser.py" > /dev/null; then
    nohup python3 "$BASE/checkuser.py" > /dev/null 2>&1 &
fi

# 5. SlowDNS
if [ -f "/etc/slowdns/priv.key" ] && [ -f "/etc/slowdns/domain" ]; then
    if ! pgrep -f "dnstt-server" > /dev/null; then
        NS=$(cat /etc/slowdns/domain 2>/dev/null || hostname)
        systemctl stop systemd-resolved &>/dev/null
        nohup /etc/slowdns/dnstt-server -udp :5353 \
            -privkey-file /etc/slowdns/priv.key "$NS" 127.0.0.1:22 > /dev/null 2>&1 &
    fi
fi

# 6. Integração com o módulo do painel web (só age se o módulo estiver
#    de fato instalado neste servidor — arquivos ausentes = no-op).
if [ -f "$BASE/dragon_hook.sh" ]; then
    bash "$BASE/dragon_hook.sh"
fi
if [ -f "$BASE/delete_watcher.sh" ] && ! pgrep -f "delete_watcher.sh" > /dev/null; then
    nohup bash "$BASE/delete_watcher.sh" >> /var/log/delete_watcher_stdout.log 2>&1 &
fi
if [ -f "$BASE/txt_watcher.sh" ] && ! pgrep -f "txt_watcher.sh" > /dev/null; then
    nohup bash "$BASE/txt_watcher.sh" >> /var/log/txt_watcher_stdout.log 2>&1 &
fi

# 7. Limpeza segura de log do Xray (somente se > 50MB)
#    NÃO apaga logs do sistema — apenas o log de acesso do Xray
if [ -f "$XRAY_LOG" ]; then
    tamanho=$(stat -c%s "$XRAY_LOG" 2>/dev/null || echo 0)
    if [ "$tamanho" -gt 52428800 ]; then
        # Mantém as últimas 1000 linhas antes de truncar
        tail -n 1000 "$XRAY_LOG" > /tmp/xray_access_last.log
        cat /tmp/xray_access_last.log > "$XRAY_LOG"
        rm -f /tmp/xray_access_last.log
    fi
fi

exit 0
