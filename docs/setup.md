# Setup

## Pré-requisitos

- Docker + Docker Compose
- openssl

```bash
docker --version
docker compose version
openssl version
```

## Subindo em produção

```bash
git clone <repo>
cd injunior-infra-base
./setup.sh
```

O script faz tudo:

1. Cria `.env` a partir do `.env.example` se não existir
2. Gera `POSTGRES_PASSWORD` e `REDIS_PASSWORD` se estiverem vazios
3. Gera `compose/redis/redis.conf` com a senha preenchida
4. Cria o diretório de backup (`BACKUP_DIR`)
5. Sobe PostgreSQL, Redis e Caddy

## Variáveis de ambiente

Todas as configurações ficam em `.env`. O `.env.example` documenta as disponíveis.

| Variável | Descrição |
| --- | --- |
| `DOMAIN_BASE` | Domínio base da VPS (ex: `cliente.com`) — **obrigatório** |
| `POSTGRES_USER` | Usuário administrador do PostgreSQL |
| `POSTGRES_DB` | Banco padrão do PostgreSQL |
| `POSTGRES_PASSWORD` | Gerado automaticamente pelo setup |
| `REDIS_PASSWORD` | Gerado automaticamente pelo setup |
| `BACKUP_DIR` | Caminho local dos backups (padrão: `/var/backups/infra`) |
| `BACKUP_RETENTION_DAYS` | Dias de retenção dos backups (padrão: `60`) |
| `TELEGRAM_BOT_TOKEN` | Token do bot para notificações (opcional) |
| `TELEGRAM_CHAT_ID` | Chat ID para notificações (opcional) |
| `RESOURCE_DISK_THRESHOLD` | % de disco para alertar (padrão: `80`) |
| `RESOURCE_RAM_THRESHOLD` | % de RAM para alertar (padrão: `85`) |
| `RCLONE_REMOTE` | Remote do rclone para upload ao Google Drive (opcional) |
| `RCLONE_PATH` | Caminho no remote (padrão: `infra/backups`) |

## Configuração de DNS

Antes de provisionar projetos, crie os registros DNS apontando para o IP da VPS:

- `api.<nome>.<DOMAIN_BASE>` — API de cada projeto

O Caddy emite certificados HTTPS automaticamente via Let's Encrypt.

## Configurar backups automáticos

```bash
./scripts/setup-cron.sh
```

Registra dois cron jobs:
- **03:00 diário** — backup completo (PostgreSQL + Redis RDB)
- **A cada hora** — verificação de uso de disco e RAM

## Criar banco e usuário manualmente

```bash
docker compose exec postgres bash /scripts/create-user-db.sh <user> <password> <db> [app|full]
```

- `app` — leitura e escrita em tabelas e sequences (padrão)
- `full` — todos os privilégios incluindo functions
