# AGENTS.md

Guia para agentes de IA (Claude, Copilot, Cursor, etc.) trabalhando neste repositório.

## Contexto

Infra base para deploy de projetos de cliente em VPS. Sobe PostgreSQL, Redis e Caddy via Docker Compose. Focado em simplicidade e operação mínima — sem serviços extras, só o necessário para hospedar backends Node.js de clientes.

## Comandos

```bash
# Setup inicial
./setup.sh

# Provisionar/remover projeto de cliente
./scripts/provision-project.sh <nome>      # cria banco + caddy site + imprime DATABASE_URL
./scripts/deprovision-project.sh <nome>    # remove banco, usuário e site do Caddy

# Criar banco/usuário em cluster já em execução
docker compose exec postgres bash /scripts/create-user-db.sh <user> <password> <db> [app|full]

# Backup
./scripts/backup.sh                        # backup manual (postgres + redis RDB)
./scripts/setup-cron.sh                   # registra backup diário (3h) + check-resources (horário)

# Verificação de recursos
./scripts/check-resources.sh              # disco e RAM vs thresholds

# Gerar secrets manualmente (preserva valores já preenchidos)
./scripts/gen-secrets.sh
```

## Decisões arquiteturais

- `setup.sh` exige `DOMAIN_BASE` no `.env` antes de subir qualquer serviço; valida isso explicitamente para evitar provisionar com domínio vazio
- Secrets (`POSTGRES_PASSWORD`, `REDIS_PASSWORD`) são gerados pelo `gen-secrets.sh` — só preenche variáveis vazias, nunca sobrescreve valores existentes
- `compose/redis/redis.conf` é gerado pelo `setup.sh` a partir do template `redis.conf.template` com a senha substituída; não é commitado no git
- `compose/caddy/Caddyfile` define apenas snippets reutilizáveis (`security_headers`, `compression`, `proxy_headers`) e `import sites/*.caddy` — nenhuma rota hardcoded; cada projeto tem seu próprio arquivo em `sites/`
- Arquivos `compose/caddy/sites/*.caddy` são gerados pelo `provision-project.sh` e ignorados pelo git (gerados em runtime); o Caddy recarrega automaticamente via `caddy reload` após cada provision/deprovision
- API dos projetos segue o padrão `api.<nome>.<DOMAIN_BASE>` — o Caddy roteia para o container `<nome>:3000` na `infra-network`
- Rede Docker: `infra-network` (bridge) — todos os containers da infra e dos projetos se comunicam por ela; projetos declaram a rede como `external: true` nos seus `docker-compose.prod.yml`
- PostgreSQL 18+ usa `PGDATA=/var/lib/postgresql/18/docker` no volume montado em `/var/lib/postgresql` — compatível com `pg_upgrade --link` em versões futuras; `--data-checksums` ativado no initdb para detecção de corrupção silenciosa
- `compose/postgres-scripts/create-user-db.sh` aceita dois modos: `app` (leitura/escrita em tabelas e sequences) e `full` (todos os privilégios incluindo functions); use `app` por padrão, `full` só para serviços que criam seus próprios objetos no banco
- Backup salva em `BACKUP_DIR` (padrão `/var/backups/infra`): `pg_dumpall` (cluster completo), um dump por banco, e Redis RDB via `BGSAVE`; retenção configurável por `BACKUP_RETENTION_DAYS` (padrão 90 dias)
- Upload opcional para Google Drive via rclone — se `RCLONE_REMOTE` estiver vazio, o passo é ignorado silenciosamente
- `check-resources.sh` alerta via Telegram quando disco ≥ `RESOURCE_DISK_THRESHOLD` ou RAM ≥ `RESOURCE_RAM_THRESHOLD`; se `TELEGRAM_BOT_TOKEN` estiver vazio, funciona sem notificar
- Todos os serviços usam `restart: unless-stopped` — reinicia em falhas e reboots, respeita `docker stop` manual
- Projetos de cliente ficam em `/home/deploy/projects/<nome>/` na VPS, fora deste repositório; cada um tem seu próprio `docker-compose.prod.yml` com `infra-network` como rede externa
