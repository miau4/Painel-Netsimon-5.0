#!/bin/bash
# ==========================================
#   NETSIMON 5.0 - DELETE WATCHER
# ==========================================
# CONTEXTO: o módulo do painel web (dragonmodule) tem um bug na
# função v2raydel — ela recebe (uuid, login) mas repassa os dois
# argumentos sem "shift" para removessh(), que só lê o primeiro
# argumento. Resultado: removessh tenta apagar um "usuário" cujo
# nome é o UUID (que não existe no Linux), e a exclusão real nunca
# se completa — o login continua com conta ativa e continua
# aparecendo em /root/usuarios.db para sempre.
#
# Esse bug está no binário/script de terceiros (dragonmodule), fora
# do nosso controle. Em vez de editar um arquivo que pode ser
# baixado de novo a qualquer momento pelo instalador do módulo, este
# script observa os comandos que o módulo recebe (via o log de
# depuração habilitado em modulo.py por dragon_hook.sh) e, sempre
# que identifica uma chamada "v2raydel" que o módulo não vai
# terminar de processar sozinho, finaliza a exclusão nós mesmos:
# mata a sessão, remove a conta Linux, limpa a senha salva e remove
# a linha de /root/usuarios.db e /etc/painel/usuarios.db.
# ==========================================

LOG="/var/log/modulo_debug.log"
[ ! -f "$LOG" ] && touch "$LOG"

tail -n0 -F "$LOG" 2>/dev/null | while read -r line; do
    case "$line" in
        *"dragonmodule v2raydel"*)
            resto="${line#*v2raydel }"
            login=$(echo "$resto" | awk '{print $2}')
            [ -z "$login" ] && continue

            # Dá tempo do dragonmodule terminar a parte que ele
            # executa corretamente (remoção do UUID no Xray) antes
            # da gente finalizar o resto.
            sleep 2

            if id "$login" &>/dev/null; then
                usermod -p "$(openssl passwd -1 "$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 20)")" "$login" 2>/dev/null
                pkill -9 -u "$login" 2>/dev/null
                userdel --force "$login" 2>/dev/null
            fi

            sed -i "/^$login /d" /root/usuarios.db 2>/dev/null
            sed -i "/^$login|/d" /etc/painel/usuarios.db 2>/dev/null
            rm -f "/etc/SSHPlus/senha/$login" 2>/dev/null

            echo "$(date '+%Y-%m-%d %H:%M:%S') | finalizada exclusao orfa: $login" >> /var/log/delete_watcher.log
            ;;
    esac
done
