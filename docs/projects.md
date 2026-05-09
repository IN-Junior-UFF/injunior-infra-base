# Projetos de cliente

## Como funciona

Cada projeto de cliente roda como um container Docker separado na mesma VPS, usando o PostgreSQL e Redis já provisionados pela infra base. O Caddy roteia o tráfego pelo subdomínio `api.<nome>.<DOMAIN_BASE>`.

## Provisionando um projeto

```bash
./scripts/provision-project.sh meu-projeto
```

O script:
1. Cria usuário e banco no PostgreSQL (`meu_projeto`)
2. Gera senha aleatória segura
3. Cria `compose/caddy/sites/meu-projeto.caddy` com o subdomínio
4. Recarrega o Caddy imediatamente

Ao final, imprime o `DATABASE_URL` completo — **copie agora**, a senha não é salva em lugar nenhum além do banco.

## Configurando DNS

Adicione um registro apontando para o IP da VPS:

- `api.meu-projeto.<DOMAIN_BASE>` → IP da VPS

O Caddy emite o certificado HTTPS na primeira requisição.

## Estrutura do projeto na VPS

Após o provision, crie o diretório do projeto e o `.env`:

```bash
mkdir -p /home/deploy/projects/meu-projeto
nano /home/deploy/projects/meu-projeto/.env
```

`.env` mínimo:

```env
NODE_ENV=production
PORT=3000

DATABASE_URL=postgresql://meu_projeto:<senha>@postgres:5432/meu_projeto
REDIS_URL=redis://:<REDIS_PASSWORD>@redis:6379/<db-index>
```

> **Redis database index**: use índices a partir de 0. Cada projeto deve usar um índice diferente para não misturar dados.

## docker-compose.prod.yml do projeto

O container do projeto precisa:

- Usar `infra-network` como rede externa para acessar postgres e redis
- Expor a porta `3000` internamente (o Caddy roteia para `<nome>:3000`)

Exemplo mínimo:

```yaml
services:
  meu-projeto:
    image: ${IMAGE}
    restart: unless-stopped
    env_file: .env
    networks:
      - infra-network

networks:
  infra-network:
    external: true
```

## Removendo um projeto

```bash
./scripts/deprovision-project.sh meu-projeto
```

Remove o banco, o usuário do PostgreSQL e o arquivo `.caddy`, e recarrega o Caddy.

Depois, remova manualmente da VPS:

```bash
rm -rf /home/deploy/projects/meu-projeto
```
