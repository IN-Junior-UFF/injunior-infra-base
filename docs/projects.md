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

### Opções disponíveis

| Flag | Descrição | Padrão |
|------|-----------|--------|
| `--prefix/-p <prefix>` | Prefixo do subdomínio. Use `@` para sem prefixo. | `api` |
| `--with-name/-n` | Inclui `<name>` no subdomínio (`api.meu-projeto.<DOMAIN_BASE>`) | — |
| `--port/-P <port>` | Porta do container para o Caddy rotear | `3000` |
| `--deploy-key` | Gera par de chaves SSH para deploy via Git | — |

Exemplos:

```bash
# subdomínio customizado
./scripts/provision-project.sh meu-projeto --prefix admin

# porta diferente de 3000
./scripts/provision-project.sh meu-projeto -P 8080

# já gera a deploy key junto
./scripts/provision-project.sh meu-projeto --deploy-key
```

### Deploy via Git (deploy key)

Para projetos que fazem clone do repositório na VPS em vez de fazer push de imagem:

**1. Provisionar com `--deploy-key`:**

```bash
./scripts/provision-project.sh meu-projeto --deploy-key
```

O script gera `~/.ssh/meu-projeto_deploy_key` e imprime a chave pública ao final.

**2. Adicionar a chave pública no GitHub:**

Repositório → Settings → Deploy keys → Add deploy key
- Colar o conteúdo impresso pelo script
- Marcar como read-only

**3. Clonar o repositório na VPS:**

```bash
./scripts/clone-project.sh meu-projeto git@github.com:org/meu-projeto.git
```

Clona em `/home/deploy/projects/meu-projeto/` usando a deploy key gerada.

## Configurando DNS

Adicione um registro apontando para o IP da VPS:

- `api.meu-projeto.<DOMAIN_BASE>` → IP da VPS

O Caddy emite o certificado HTTPS na primeira requisição.

## Estrutura do projeto na VPS

Após o provision (e clone, se aplicável), crie o `.env`:

```bash
# sem deploy key — crie o diretório manualmente
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
- Expor a porta internamente na mesma porta configurada no provision (padrão `3000`)

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
