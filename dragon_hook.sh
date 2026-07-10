#!/bin/bash
# ==========================================
#   NETSIMON 5.0 - DRAGON HOOK
# ==========================================
# O delete_watcher.sh precisa ver, em tempo real, quais comandos o
# módulo do painel (modulo.py, na porta 6969) está executando — é
# assim que detectamos uma exclusão (v2raydel) que precisa ser
# finalizada. modulo.py pertence a um instalador externo
# (module.dragoncoressh.com) e pode ser baixado de novo a qualquer
# momento por fora do Netsimon, sem esse log.
#
# Este script roda a cada minuto (cron) e, de forma NÃO destrutiva:
#   1. Verifica se /root/modulo.py já tem o log de depuração.
#   2. Se não tiver, insere só essa linha (sem tocar em mais nada
#      do arquivo) logo após ler o comando recebido.
#   3. Reinicia o modulo.py SOMENTE se acabou de aplicar o patch.
#
# Se o painel ainda não usa esse módulo (arquivo não existe), o
# script não faz nada — seguro rodar em qualquer servidor.
# ==========================================

MODULO="/root/modulo.py"
MARCA="modulo_debug.log"

[ ! -f "$MODULO" ] && exit 0
grep -q "$MARCA" "$MODULO" 2>/dev/null && exit 0

python3 - "$MODULO" "$MARCA" <<'PYEOF'
import sys

path, marca = sys.argv[1], sys.argv[2]
with open(path, "r") as f:
    content = f.read()

marker = "comando = form.getvalue('comando') or ''"
if marker in content and marca not in content:
    patch = (
        marker + "\n"
        "                with open('/var/log/modulo_debug.log', 'a') as _dbgf:\n"
        "                    import datetime as _dt\n"
        "                    _dbgf.write(str(_dt.datetime.now()) + ' | ' + comando + chr(10))"
    )
    content = content.replace(marker, patch, 1)
    with open(path, "w") as f:
        f.write(content)
PYEOF

if grep -q "$MARCA" "$MODULO" 2>/dev/null; then
    pkill -9 -f "modulo.py" 2>/dev/null
    sleep 1
    cd /root && nohup python3 /root/modulo.py > /var/log/modulo_stdout.log 2>&1 &
fi
