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
| `--no-db` | Pula a criação de usuário/banco no PostgreSQL (ex: frontends) | — |
| `--no-csp` | Omite o header `Content-Security-Policy` do Caddy (ex: Next.js) | — |

Exemplos:

```bash
# subdomínio customizado
./scripts/provision-project.sh meu-projeto --prefix admin

# porta diferente de 3000
./scripts/provision-project.sh meu-projeto -P 8080

# já gera a deploy key junto
./scripts/provision-project.sh meu-projeto --deploy-key

# frontend Next.js (sem banco, sem CSP)
./scripts/provision-project.sh meu-frontend --prefix @ --port 3000 --no-db --no-csp --deploy-key
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

- Usar a rede da infra como rede externa para acessar postgres e redis. O nome real dela é **`infra-base_infra-network`**: o Compose prefixa a rede com o nome do projeto, que é o nome da pasta (`infra-base`). Por isso o `name:` é obrigatório. Sem ele, o Compose procura uma rede chamada literalmente `infra-network` e falha com `network infra-network declared as external, but could not be found`.
- Ter o serviço (ou `hostname:`) com o **mesmo nome** usado no `provision-project.sh`, porque o Caddy faz `reverse_proxy <nome>:<porta>`
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
    name: infra-base_infra-network
```

## Frontend estático (SPA) servido pelo próprio Caddy

Para um frontend que compila para arquivos estáticos (Vite/React, Vue etc.), não é preciso container: o Caddy da infra serve o `dist/` direto. A pasta `compose/caddy/` já é montada no Caddy em `/etc/caddy`, e `compose/caddy/www/` é ignorada pelo git.

O `provision-project.sh` só gera `reverse_proxy`, então o site é escrito à mão em `compose/caddy/sites/<nome>.caddy`:

```caddy
meu-dominio.com {
	import compression
	import security_headers
	root * /etc/caddy/www/<nome>
	@notAssets not path /assets/*
	header @notAssets Cache-Control "no-cache"
	header /assets/* Cache-Control "public, max-age=31536000, immutable"
	try_files {path} /index.html
	file_server
}

# opcional: www → domínio principal
www.meu-dominio.com {
	redir https://meu-dominio.com{uri} permanent
}
```

Depois, recarregue: `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`.

- `try_files {path} /index.html` faz rotas do SPA (`/pacientes/123`) devolverem o `index.html` em vez de 404.
- Os assets do Vite têm hash no nome, por isso o cache é longo. O `index.html` é `no-cache`, para o deploy aparecer na hora.

**Deploy pelo CI, com versões e rollback instantâneo:** cada deploy vira uma pasta em `www/<nome>-releases/<data>-<sha>`, e `www/<nome>` (o `root` do Caddy) é um **symlink** para a versão ativa. A troca é um `rename` atômico do link, então ninguém recebe um `index.html` novo apontando para assets que ainda não chegaram. As últimas versões continuam guardadas, e voltar é só reapontar o link, sem rebuild. O Caddy segue o symlink normalmente, porque o caminho relativo fica dentro da pasta montada.

Faça tudo **numa conexão SSH só**: o UFW do bootstrap (`injunior-infra-ansible`) usa `LIMIT` na porta SSH e bloqueia por 30s o IP que abrir 6 ou mais conexões em 30s. A `appleboy/scp-action` abre várias seguidas e cai nesse bloqueio.

```bash
tar -C dist -czf - . | ssh -p "$PORT" deploy@"$HOST" '
  set -e; cd /home/deploy/infra-base/compose/caddy/www
  R=<nome>-releases; KEEP=5; mkdir -p "$R"
  IN="$R/.incoming-$$"; mkdir "$IN"; tar -xzf - -C "$IN"
  test -f "$IN/index.html"
  NEW="$R/$(date -u +%Y%m%dT%H%M%S)-'"${GITHUB_SHA::7}"'"; mv "$IN" "$NEW"
  ln -sfn "$NEW" .<nome>.tmp && mv -T .<nome>.tmp <nome>
  ACTIVE=$(readlink <nome>)
  ls -1d "$R"/*/ | sed "s#/\$##" | sort -r | tail -n +$((KEEP + 1)) \
    | while read -r old; do [ "$old" = "$ACTIVE" ] || rm -rf "$old"; done'
```

Rollback para uma versão guardada:

```bash
cd /home/deploy/infra-base/compose/caddy/www
ls <nome>-releases                       # versões disponíveis
ln -sfn <nome>-releases/<versão> .<nome>.tmp && mv -T .<nome>.tmp <nome>
```

Para uma implementação completa, com workflow de deploy e de rollback (versão anterior ou escolhida pelo nome), veja o `frontend-sistema-mex` (`.github/workflows/deploy-production.yml` e `rollback-production.yml`).

O `deprovision-project.sh` remove o `.caddy`, mas não `compose/caddy/www/<nome>` nem `<nome>-releases/`. Apague as duas à mão.

## Removendo um projeto

```bash
./scripts/deprovision-project.sh meu-projeto
```

Remove o banco, o usuário do PostgreSQL, o arquivo `.caddy`, recarrega o Caddy e, se existir, a deploy key em `~/.ssh/meu-projeto_deploy_key`.

Depois, remova manualmente o diretório do projeto da VPS:

```bash
rm -rf /home/deploy/projects/meu-projeto
```
