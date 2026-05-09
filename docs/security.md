# Segurança (Caddy)

## Headers aplicados a todos os serviços

O snippet `security_headers` no `Caddyfile` aplica automaticamente:

| Header | O que faz |
| --- | --- |
| `Strict-Transport-Security` | Força HTTPS — o browser nunca tenta HTTP |
| `X-Content-Type-Options: nosniff` | Impede o browser de adivinhar o tipo de arquivo |
| `X-Frame-Options: SAMEORIGIN` | Bloqueia carregamento em `<iframe>` de outro domínio (previne clickjacking) |
| `Referrer-Policy` | Controla quanta informação da URL é enviada ao clicar em links externos |
| `Permissions-Policy` | Desabilita acesso a câmera, microfone e geolocalização |
| `Server` | Remove o header que identifica o servidor |

## Content-Security-Policy dos projetos

Os arquivos `.caddy` gerados pelo `provision-project.sh` usam uma política conservadora por padrão:

```text
default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'
```

Se o backend precisar aceitar requisições de outras origens (ex: frontend no GitHub Pages ou domínio próprio do cliente), edite o arquivo em `compose/caddy/sites/<nome>.caddy` e recarregue o Caddy:

```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

## Debugando bloqueios de CSP

Se algo não carregar após um deploy, verifique o console do browser (F12 → Console). Erros de CSP aparecem assim:

```text
Refused to load script from 'https://cdn.example.com/lib.js' because it violates
the following Content Security Policy directive: "script-src 'self'"
```

Ajuste a diretiva no arquivo `.caddy` do projeto e recarregue o Caddy.

Exemplos comuns:

- Script externo bloqueado: adicione o domínio em `script-src`
- Imagem de CDN bloqueada: adicione o domínio em `img-src`
- WebSocket bloqueado: adicione `wss:` em `connect-src`
- SPA com estilos inline: adicione `'unsafe-inline'` em `style-src`

## CORS

O Caddy não configura CORS por padrão. Se o frontend (em domínio diferente) precisar fazer chamadas à API, adicione no arquivo `.caddy` do projeto:

```caddy
api.meu-projeto.cliente.com {
    @options method OPTIONS
    handle @options {
        header Access-Control-Allow-Origin "https://meu-projeto.cliente.com"
        header Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
        header Access-Control-Allow-Headers "Content-Type, Authorization"
        respond "" 204
    }

    import compression
    import security_headers
    reverse_proxy meu-projeto:3000 {
        import proxy_headers
    }
}
```
