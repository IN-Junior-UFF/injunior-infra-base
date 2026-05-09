# Backup

## O que é salvo

Cada execução gera um conjunto de arquivos com o mesmo timestamp em `BACKUP_DIR` (padrão `/var/backups/infra`):

| Arquivo | Conteúdo |
| --- | --- |
| `YYYY-MM-DD_HH-MM.all.sql.gz` | Dump completo do PostgreSQL — todos os bancos, usuários e permissões |
| `YYYY-MM-DD_HH-MM.<banco>.sql.gz` | Dump individual por banco (um por projeto) |
| `YYYY-MM-DD_HH-MM.redis.rdb` | Snapshot do Redis (BGSAVE) |

Todos os arquivos têm permissão `600`.

## Backup manual

```bash
./scripts/backup.sh
```

Útil antes de atualizações ou mudanças de configuração relevantes.

## Backup automático via cron

Execute uma vez após o setup para registrar os jobs:

```bash
./scripts/setup-cron.sh
```

Registra dois jobs no crontab:

- **03:00 diário** — backup completo com rotação
- **todo hora** — verificação de recursos (disco e RAM)

Para confirmar o registro:

```bash
crontab -l
```

Para acompanhar os logs:

```bash
tail -f /var/log/infra-backup.log
```

## Retenção

Padrão: 90 dias. Configure no `.env`:

```env
BACKUP_RETENTION_DAYS=90
```

A rotação se aplica tanto nos arquivos locais quanto no Google Drive (se configurado).

## Upload para Google Drive

Após cada backup, o `backup.sh` envia os arquivos do dia para o Google Drive se `RCLONE_REMOTE` estiver preenchido. Se estiver vazio, o passo é ignorado.

### Configurando o rclone

**1. Instalar na VPS:**

```bash
curl https://rclone.org/install.sh | sudo bash
```

**2. Autenticar com Google Drive** (sem browser na VPS, use autenticação remota):

```bash
rclone config
```

Passos:
1. `n` → new remote
2. Nome: `gdrive`
3. Tipo: `drive`
4. Client ID e Secret: deixe em branco
5. Scope: `1` (acesso completo)
6. `n` → não usar auto config
7. Abra a URL exibida no seu computador, autorize e cole o código de volta
8. `n` → não configurar como Shared Drive
9. `y` → confirma

Teste:

```bash
rclone ls gdrive:
```

**3. Configurar no `.env`:**

```env
RCLONE_REMOTE=gdrive
RCLONE_PATH=infra/backups
```

## Notificações via Telegram

Se `TELEGRAM_BOT_TOKEN` e `TELEGRAM_CHAT_ID` estiverem preenchidos, o `backup.sh` envia:

- Resumo ao concluir (contagem de arquivos e tamanho total)
- Alerta em caso de falha com instrução para verificar os logs

Para configurar:

1. Crie um bot no [@BotFather](https://t.me/BotFather) e copie o token
2. Obtenha o `chat_id` (adicione o bot a um grupo, mande uma mensagem e acesse `api.telegram.org/bot<TOKEN>/getUpdates`)
3. Preencha no `.env`:

```env
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
TELEGRAM_CHAT_ID=-1001234567890
```

## Restaurando

O backup gera arquivos SQL compatíveis com `psql` e `pg_restore`. Para restaurar um banco específico:

```bash
# Restaurar um banco individual
gunzip -c /var/backups/infra/2026-05-09_03-00.meu_projeto.sql.gz \
  | docker compose exec -T postgres psql -U postgres meu_projeto

# Restaurar o cluster inteiro (migração ou desastre total)
gunzip -c /var/backups/infra/2026-05-09_03-00.all.sql.gz \
  | docker compose exec -T postgres psql -U postgres
```

Para o Redis RDB:

```bash
# Pare o Redis, copie o arquivo para o volume e reinicie
docker compose stop redis
docker run --rm \
  -v infra-base_redis_data:/data \
  -v /var/backups/infra:/backup \
  alpine cp /backup/2026-05-09_03-00.redis.rdb /data/dump.rdb
docker compose start redis
```
