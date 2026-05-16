# Gerenciamento de Serviços

O `scripts/service.sh` é a interface principal para operar os serviços da infra no dia a dia.

## Uso

```bash
./scripts/service.sh <comando> [serviço]
```

## Comandos

### Status e saúde

```bash
./scripts/service.sh status   # lista todos os serviços com uso de CPU, RAM e disco do host
./scripts/service.sh health   # mostra apenas containers unhealthy ou reiniciando
```

### Logs

```bash
./scripts/service.sh logs <serviço>
```

Para aumentar o número de linhas:

```bash
LINES=200 ./scripts/service.sh logs postgres
```

### Ciclo de vida

```bash
./scripts/service.sh start    <serviço>   # inicia um serviço parado
./scripts/service.sh stop     <serviço>   # para o serviço (pede confirmação para postgres e redis)
./scripts/service.sh restart  <serviço>   # reinicia sem recriar o container
./scripts/service.sh recreate <serviço>   # recria o container (aplica mudanças de config ou .env)
./scripts/service.sh update   <serviço>   # faz pull da imagem e recria
```

Serviços críticos (`postgres` e `redis`) pedem confirmação antes de parar.

### Backup e restauração

```bash
./scripts/service.sh backup                        # executa backup completo (PostgreSQL + Redis)
./scripts/service.sh restore <arquivo>             # restaura a partir de um arquivo de backup
```

O `restore` detecta o tipo de arquivo automaticamente:

| Arquivo | Ação |
| --- | --- |
| `*.all.sql.gz` | Restaura o cluster inteiro do PostgreSQL |
| `*.<banco>.sql.gz` | Restaura um banco individual |
| `*.redis.rdb` | Para o Redis, restaura o RDB e reinicia |

Operações destrutivas pedem confirmação antes de executar.

## Exemplos

```bash
# Ver status geral
./scripts/service.sh status

# Aplicar mudança no .env do caddy
./scripts/service.sh recreate caddy

# Atualizar imagem do postgres
./scripts/service.sh update postgres

# Restaurar banco de um projeto específico
./scripts/service.sh restore /var/backups/infra/2026-05-16_03-00.meu_projeto.sql.gz
```
