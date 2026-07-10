# 🚀 Painel Netsimon 5.0

Painel de gerenciamento para VPS de SSH/VLESS (Xray), com WebSocket, SlowDNS, limitador de conexões simultâneas e integração nativa com o módulo web do painel (Dragon Core).

## Instalação

Escolha um dos três comandos abaixo, rodando como **root** na sua VPS.

### 1. Instalação direta (sempre a versão mais recente, sem cache)

```bash
bash <(curl -sSL "https://raw.githubusercontent.com/miau4/Painel-Netsimon-5.0/main/install.sh?t=$(date +%s)")
```

### 2. Instalação com atualização do sistema (apt update/upgrade antes)

```bash
apt update -y && apt upgrade -y && bash <(curl -sSL "https://raw.githubusercontent.com/miau4/Painel-Netsimon-5.0/main/install.sh?t=$(date +%s)")
```

### 3. Limpeza de instalação anterior

Encerra processos e crons de uma instalação antiga do Netsimon (sem apagar `usuarios.db` ou configurações). Rode este comando primeiro se está reinstalando por cima de uma versão anterior, e em seguida rode um dos comandos acima.

```bash
bash <(curl -sSL "https://raw.githubusercontent.com/miau4/Painel-Netsimon-5.0/main/cleanup.sh?t=$(date +%s)")
```

Depois de instalar, digite `menu` a qualquer momento para abrir o painel.

## O que a instalação já deixa pronto

- Xray instalado, configurado (VLESS + xHTTP + TLS) e rodando como serviço systemd
- Portas WebSocket 80 e 8080 já ativas
- Nginx (porta 81, com PHP-FPM) e Stunnel (porta 8443)
- Limitador de conexões ativo
- Integração com o módulo do painel web pronta (ver seção abaixo)

## Menu principal

```
01) Gerenciar Usuários     — criar, remover, listar, ver online, bloqueios
02) Gerenciar Conexões     — WebSocket, SlowDNS, Xray, CheckUser API
03) Status VPS             — recursos do servidor e portas em uso
04) Teste Velocidade
05) EXTRAS                 — limiter, backup, logs
06) Reparar Sistema        — restaura todos os arquivos do painel
```

O cabeçalho do menu principal mostra, em tempo real: total de usuários, quantos estão online agora, quantos expiraram e o status do bloqueio por dispositivo (ver abaixo). A contagem de "online" é sempre a mesma em qualquer tela do painel — cabeçalho, submenu de usuários e Xray Manager consultam a mesma fonte, não existem dois números divergentes.

## Integração com o módulo do painel web

O Netsimon fica lado a lado com o módulo oficial do painel web (instalado separadamente, a partir do provedor do seu painel — o processo que escuta na porta `6969` e recebe comandos de criação/remoção de usuário). Esse módulo só grava `login` e `limite` no banco dele; UUID, validade e senha ficam guardados em outros lugares (config do Xray, conta do sistema Linux, e uma pasta de senhas). Três scripts do Netsimon cuidam de juntar tudo isso automaticamente, sem qualquer configuração manual:

- **`sync_usuarios.sh`** — roda a cada minuto, busca UUID/validade/senha nas fontes reais e mantém o banco do painel sempre correto, sem nunca duplicar ou trocar dados de usuários já existentes.
- **`delete_watcher.sh`** — finaliza exclusões que o módulo às vezes não completa sozinho (conta, senha e registro do usuário).
- **`dragon_hook.sh`** — mantém o módulo do painel preparado para o `delete_watcher.sh` funcionar, mesmo que o módulo seja reinstalado depois por fora do Netsimon.

Tudo isso é configurado automaticamente pelo instalador — inclusive as pastas que o módulo precisa para gravar dados corretamente. Se o módulo do painel ainda não estiver instalado neste servidor, esses três scripts simplesmente não fazem nada (sem erros, sem impacto no resto do painel).

## Bloqueio por dispositivo (opcional)

O Netsimon reconhece um sistema opcional e independente de bloqueio por dispositivo no aplicativo do cliente, instalado manualmente a partir de:

`https://github.com/miau4/script-de-instala-o-do-bloqueio-de-usuarios-no-app`

Se esse script estiver instalado, o menu de usuários ganha as opções **"Liberar Todos"** e **"Liberar 1 Usuário"**, e o status "Block" no cabeçalho passa a refletir quantos usuários estão sob esse controle. Sem ele instalado, o painel mostra "N/A" nesse campo e as opções de liberação avisam que o sistema não está presente — nada quebra.

## Limitador de conexões

O limitador (`limit.sh`) tem uma responsabilidade única: expulsar sessões SSH/Xray duplicadas acima do limite contratado por usuário. Ele não participa da sincronização de usuários de forma alguma — pode ficar ligado ou desligado a qualquer momento (opção EXTRAS do menu) sem afetar criação, remoção ou sincronização de ninguém.

## Estrutura de arquivos

| Arquivo | Função |
|---|---|
| `install.sh` | Instalador completo |
| `menu.sh` | Painel principal |
| `adduser.sh` / `addtest.sh` / `deluser.sh` | Criação e remoção de usuários (fluxo local) |
| `online.sh` | Biblioteca + tela de usuários online |
| `xray.sh` / `xray_lib.sh` | Gerenciamento do Xray |
| `websocket.sh` | Gerenciamento das portas WebSocket |
| `slowdns-server.sh` | Gerenciamento do SlowDNS |
| `checkuser.py` / `checkuser.sh` | API de consulta de usuários (porta 5000) |
| `limit.sh` | Limitador de conexões simultâneas |
| `unblock.sh` | Restaura acesso de um usuário expulso pelo limiter (uso manual, fora do menu) |
| `sync_usuarios.sh` | Converge dados do módulo do painel web |
| `delete_watcher.sh` | Finaliza exclusões incompletas do módulo |
| `dragon_hook.sh` | Mantém a integração com o módulo sempre ativa |
| `boot_check.sh` | Auto-recuperação de todos os serviços no boot |
| `repair.sh` | Restaura todos os arquivos a partir do repositório |
| `cleanup.sh` | Limpeza de instalação anterior |
| `proxy.py` | Proxy WebSocket/SSH |
| `monitor.sh` | Status detalhado da VPS |
| `xray.service` / `config.json.template` | Referência de configuração do Xray |

## Requisitos

- Ubuntu/Debian
- Acesso root
- VPS com IP público
