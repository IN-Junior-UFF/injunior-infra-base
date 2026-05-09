# Manutenção

## Verificar saúde dos serviços

```bash
docker compose ps
docker compose logs --tail=50 <serviço>
```

Para ver todos os containers com problema (unhealthy ou reiniciando):

```bash
docker compose ps --filter "status=restarting"
docker ps --filter "health=unhealthy"
```

## Atualizar uma imagem

```bash
docker compose pull <serviço>
docker compose up -d --force-recreate <serviço>
docker compose logs -f <serviço>
```

Faça sempre um backup antes de atualizar o PostgreSQL ou o Redis.

## Aplicar mudanças de configuração

Após editar o `.env` ou um arquivo de configuração montado como volume:

```bash
docker compose up -d --force-recreate <serviço>
```

Para o Caddy especificamente (sem downtime):

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Alertas de recursos

O `scripts/check-resources.sh` verifica uso de disco e RAM e envia notificação no Telegram quando os thresholds forem ultrapassados. É registrado pelo `setup-cron.sh` para rodar toda hora.

Saída quando tudo está ok:

```text
[check-resources] OK — disk: 42%, ram: 61%
```

Para acompanhar o log:

```bash
tail -f /var/log/infra-resources.log
```

Thresholds configuráveis no `.env`:

```env
RESOURCE_DISK_THRESHOLD=80
RESOURCE_RAM_THRESHOLD=85
```

## Remover imagens antigas

Após atualizações, imagens antigas ficam acumuladas no disco:

```bash
docker image prune -f
```

## Verificar espaço em disco

```bash
df -h /
du -sh /var/backups/infra/
docker system df
```
