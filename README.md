# injunior-infra-base

Infra base para deploy de projetos de cliente em VPS. Sobe PostgreSQL, Redis e Caddy via Docker Compose e fornece scripts para provisionar e gerenciar projetos.

## Pré-requisitos

- Docker + Docker Compose
- openssl

## Setup

```bash
git clone <repo>
cd injunior-infra-base

# Configurar rotação de logs do Docker (uma vez, como root)
sudo ./scripts/setup-docker-logs.sh
sudo systemctl restart docker

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

## Gerenciamento de serviços

```bash
./scripts/service.sh status            # status + recursos
./scripts/service.sh update <serviço>  # pull + recreate
./scripts/service.sh restore <arquivo> # restaurar backup
```

## Documentação

- [docs/setup.md](docs/setup.md) — setup detalhado e variáveis de ambiente
- [docs/projects.md](docs/projects.md) — ciclo de vida de projetos de cliente
- [docs/backup.md](docs/backup.md) — backup, restauração e Google Drive
- [docs/maintenance.md](docs/maintenance.md) — manutenção e atualização de serviços
- [docs/service.md](docs/service.md) — referência completa do scripts/service.sh
- [docs/security.md](docs/security.md) — headers de segurança e CORS no Caddy
