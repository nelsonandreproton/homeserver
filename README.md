# homeserver

Orquestrador central de todos os serviços do servidor pessoal.
Um único `docker-compose.yml` gere tudo; cada repositório mantém o seu próprio `deploy.sh` para atualizações individuais.

## Serviços

| Contentor | Repo | Descrição |
|---|---|---|
| `cncsearch` | `../CNCSearch` | Web UI de pesquisa semântica de cânticos litúrgicos |
| `cncsearch_caddy` | — | Reverse proxy com HTTPS automático via sslip.io |
| `garminbot` | `../GarminBot` | Bot Telegram com dados Garmin, cânticos e estado do servidor |
| `hetzner-monitor` | `../HetznerCheck` | Monitor de métricas do servidor com alertas e resumo diário |

## Estrutura de diretórios esperada

```
/opt/
├── homeserver/       ← este repositório
├── CNCSearch/
├── GarminBot/
└── HetznerCheck/
```

Todos os repositórios devem ser irmãos no mesmo diretório pai.

## Pré-requisitos

- Docker Engine ≥ 24 com o plugin `docker compose` (v2)
- Git
- Acesso root ou utilizador no grupo `docker`

## Primeira instalação

### 1. Clonar todos os repositórios

```bash
cd /opt
git clone <url-homeserver>   homeserver
git clone <url-cncsearch>    CNCSearch
git clone <url-garminbot>    GarminBot
git clone <url-hetznercheck> HetznerCheck
```

### 2. Configurar o homeserver

```bash
cd /opt/homeserver
cp .env.example .env
```

Editar `.env`:

| Variável | Descrição |
|---|---|
| `CADDY_HOST` | IP do servidor com traços + `.sslip.io` — ex: `1-2-3-4.sslip.io` |
| `DOCKER_GID` | GID do grupo `docker` no host: `getent group docker \| cut -d: -f3` |
| `EMBEDDING_PROVIDER` | `jina` (padrão) ou `local` |
| `JINA_API_KEY` | Chave da API Jina AI (conta gratuita em [jina.ai](https://jina.ai)) |

### 3. Configurar cada serviço

Cada serviço tem o seu próprio `.env` com as suas credenciais:

**CNCSearch** — `../CNCSearch/.env`:
```bash
cd /opt/CNCSearch && cp .env.example .env
```
| Variável | Descrição |
|---|---|
| `WEB_SECRET_KEY` | Chave aleatória para cookies: `python3 -c "import secrets; print(secrets.token_hex(32))"` |
| `WEB_INITIAL_PASSWORD` | Password inicial do painel web |
| `JINA_API_KEY` | Igual ao homeserver `.env` |
| `EMBEDDING_PROVIDER` | `jina` ou `local` |

**GarminBot** — `../GarminBot/.env`:
```bash
cd /opt/GarminBot && cp .env.example .env
```
| Variável | Descrição |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Token do bot (via @BotFather) |
| `TELEGRAM_CHAT_ID` | ID do chat autorizado |
| `GARMIN_EMAIL` | Email da conta Garmin Connect |
| `GARMIN_PASSWORD` | Password da conta Garmin Connect |

**HetznerCheck** — `../HetznerCheck/.env`:
```bash
cd /opt/HetznerCheck && cp .env.example .env
```
| Variável | Descrição |
|---|---|
| `TELEGRAM_BOT_TOKEN` | Token do bot (pode ser o mesmo do GarminBot) |
| `TELEGRAM_CHAT_ID` | ID do chat para alertas e resumo diário |

### 4. Arrancar

```bash
cd /opt/homeserver
docker compose up -d --build
```

Verificar se tudo está a correr:

```bash
docker compose ps
```

## Deploy

### Atualizar tudo

```bash
cd /opt/homeserver
bash deploy.sh
```

Faz `git pull` em todos os repositórios, reconstrói todas as imagens e reinicia todos os serviços.

### Atualizar um serviço individualmente

```bash
# Só o CNCSearch (+ Caddy)
cd /opt/CNCSearch && bash deploy.sh

# Só o GarminBot
cd /opt/GarminBot && bash deploy.sh

# Só o HetznerCheck
cd /opt/HetznerCheck && bash deploy.sh
```

Cada `deploy.sh` faz `git pull` no seu próprio repositório e usa o `docker-compose.yml` central para reconstruir apenas o(s) seu(s) contentor(es).

## Comandos úteis

```bash
# Ver estado de todos os contentores
docker compose ps

# Logs em tempo real (todos)
docker compose logs -f --tail=30

# Logs de um serviço específico
docker compose logs -f --tail=50 garminbot
docker compose logs -f --tail=50 cncsearch
docker compose logs -f --tail=50 hetzner-monitor

# Reiniciar um serviço sem reconstruir
docker compose restart garminbot

# Parar tudo
docker compose down

# Parar e apagar volumes (CUIDADO: apaga dados)
docker compose down -v
```

## Arquitetura

```
Internet
    │
    │ :80/:443
    ▼
┌─────────────┐
│    Caddy    │  HTTPS automático via sslip.io
│  (reverse   │
│   proxy)    │
└──────┬──────┘
       │ :8080 (interno)
       ▼
┌─────────────┐         volume: cncsearch_data
│  CNCSearch  │◄────────────────────────────────┐
│  (web UI)   │                                 │
└─────────────┘                                 │
                                                │
┌─────────────┐  volume: cncsearch_data         │
│  GarminBot  │◄────────────────────────────────┘
│  (Telegram) │
│             │  monta: /CNCSearch (código)
│  /canticos  │         /HetznerCheck (código)
│  /server_   │         /rootfs, /var/log, /docker.sock
│   status    │
└─────────────┘

┌──────────────────┐
│  hetzner-monitor │  alertas e resumo diário via Telegram
│  (HetznerCheck)  │  monta: /rootfs, /var/log, /docker.sock
└──────────────────┘
```

## Comandos Telegram disponíveis

| Comando | Descrição |
|---|---|
| `/canticos [N] [-m momento] texto` | Pesquisa semântica de cânticos (CNCSearch) |
| `/server_status` | Estado atual do servidor: CPU, RAM, disco, Docker, SSH (HetznerCheck) |
| `/hoje` | Resumo diário Garmin |
| `/sync` | Sincronização manual com Garmin Connect |

## Segurança

- **`homeserver/.env`** — apenas variáveis de interpolação do compose (sem credenciais críticas)
- **Credenciais por serviço** — cada repo gere o seu `.env`; nenhum ficheiro `.env` é versionado
- **Volumes de sistema** (`/rootfs`, `/var/log`, `/docker.sock`) montados em modo **read-only** nos contentores que precisam de métricas do host
- **`pid: host`** e **`network_mode: host`** apenas nos contentores que precisam de ver processos e tráfego reais do host (`garminbot`, `hetzner-monitor`)
