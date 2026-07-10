#!/bin/bash
# ==========================================
#   NETSIMON 5.0 - TXT WATCHER
# ==========================================
# CONTEXTO: quando o painel web cria um usuário (SSH ou VLESS), ele
# grava um arquivo temporário /root/<hash>.txt e o módulo do painel
# (modulo.py) chama "python3 sincronizar.py <arquivo>" para
# processá-lo — mas só quando o comando chega via requisição HTTP
# comum. Em alguns fluxos do painel (sincronização em massa) o
# arquivo é criado sem esse comando disparar automaticamente, e o
# usuário nunca é processado. Este watcher cobre essa lacuna:
# observa /root/ e processa qualquer .txt de CRIAÇÃO que apareça.
#
# ATENÇÃO — NUNCA processar arquivos de EXCLUSÃO aqui: o mesmo padrão
# de nome (hash aleatório + .txt) é usado tanto por sincronizar.py
# (criação) quanto por delete.py (exclusão). Se este watcher rodar
# sincronizar.py em cima de um arquivo de exclusão, ele RECRIA o
# usuário que acabou de ser removido. Os dois formatos são
# diferentes e é assim que este script diferencia:
#   Criação (sincronizar.py): "login senha dias limite [uuid]"   → 4 ou 5 campos
#   Exclusão (delete.py):     "login uuid" ou só "login"          → 1 ou 2 campos
# Arquivos com 2 campos ou menos são sempre ignorados aqui.
# ==========================================

IGNORAR=("antes.txt" "depois.txt" "antes_etc.txt" "depois_etc.txt" \
         "diagnostico_modulo.txt" "log_instalacao_modulo.txt")

deve_ignorar_nome() {
    local nome="$1"
    for skip in "${IGNORAR[@]}"; do
        [[ "$nome" == "$skip" ]] && return 0
    done
    return 1
}

inotifywait -m -e close_write -e moved_to /root/ --format '%f' 2>/dev/null | while read -r fname; do
    [[ "$fname" != *.txt ]] && continue
    deve_ignorar_nome "$fname" && continue

    filepath="/root/$fname"
    [ ! -f "$filepath" ] && continue
    sleep 1
    [ ! -f "$filepath" ] && continue

    campos=$(head -n1 "$filepath" 2>/dev/null | awk '{print NF}')
    if [[ -z "$campos" || "$campos" -le 2 ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') | ignorado (exclusao ou vazio): $fname" >> /var/log/txt_watcher.log
        continue
    fi

    cd /root && python3 /root/sincronizar.py "$filepath" 2>/dev/null
    echo "$(date '+%Y-%m-%d %H:%M:%S') | processado (criacao): $fname" >> /var/log/txt_watcher.log
done
