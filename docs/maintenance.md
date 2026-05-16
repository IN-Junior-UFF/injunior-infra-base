# Manutenção

## Gerenciar serviços com service.sh

O `scripts/service.sh` centraliza as operações mais comuns:

```bash
./scripts/service.sh status              # status e uso de recursos de todos os serviços
./scripts/service.sh health              # apenas containers unhealthy ou reiniciando
./scripts/service.sh logs <serviço>      # tail de logs (LINES=200 para mais linhas)
./scripts/service.sh restart <serviço>   # reiniciar
./scripts/service.sh update <serviço>    # pull da imagem + recreate
./scripts/service.sh recreate <serviço>  # recreate sem pull (aplica mudanças de config)
./scripts/service.sh start <serviço>     # iniciar serviço parado
./scripts/service.sh stop <serviço>      # parar (pede confirmação para postgres e redis)
./scripts/service.sh backup              # backup manual completo
./scripts/service.sh restore <arquivo>   # restaurar backup (SQL ou RDB)
```

Faça sempre um backup antes de atualizar o PostgreSQL ou o Redis.

## Aplicar mudanças de configuração

Para o Caddy especificamente (sem downtime):

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Alertas de recursos

O `scripts/check-resources.sh` verifica uso de disco, RAM e CPU, e envia notificação no Telegram quando os thresholds forem ultrapassados. É registrado pelo `setup-cron.sh` para rodar toda hora.

Saída quando tudo está ok:

```text
[check-resources] OK — disk: 42%, ram: 61%, cpu: 15%
```

Para acompanhar o log:

```bash
tail -f /var/log/infra-resources.log
```

Thresholds e controle de notificações configuráveis no `.env`:

```env
RESOURCE_DISK_THRESHOLD=80
RESOURCE_RAM_THRESHOLD=85
RESOURCE_CPU_THRESHOLD=90
RESOURCES_TELEGRAM_ENABLED=true
```

## Configurar rotação de logs do Docker

Execute uma vez como root antes do setup para evitar acúmulo de logs nos containers:

```bash
sudo ./scripts/setup-docker-logs.sh
sudo systemctl restart docker
```

Configura limite de 7 arquivos × 50 MB por container (~350 MB máx).

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
