# injunior-infra-base

Infra base para deploy de projetos de cliente em VPS. Sobe PostgreSQL, Redis e Caddy via Docker Compose e fornece scripts para provisionar e gerenciar projetos.

## Pré-requisitos

- Docker + Docker Compose
- openssl

## Setup

```bash
git clone <repo>
cd injunior-infra-base

# Edite o .env após a cópia e defina DOMAIN_BASE
./setup.sh
```

O `setup.sh`:
1. Cria `.env` a partir do `.env.example`
2. Gera secrets (POSTGRES_PASSWORD, REDIS_PASSWORD)
3. Gera `compose/redis/redis.conf`
4. Sobe PostgreSQL, Redis e Caddy

## Projetos

```bash
# Provisionar
./scripts/provision-project.sh meu-projeto

# Remover
./scripts/deprovision-project.sh meu-projeto
```

## Backup

```bash
# Configurar cron (roda teste de backup antes de registrar)
./scripts/setup-cron.sh

# Rodar manualmente
./scripts/backup.sh
```

Backups salvos em `BACKUP_DIR` (padrão `/var/backups/infra`). Retenção configurável via `BACKUP_RETENTION_DAYS`.

## Documentação

- [docs/setup.md](docs/setup.md) — setup detalhado e variáveis de ambiente
- [docs/projects.md](docs/projects.md) — ciclo de vida de projetos de cliente
