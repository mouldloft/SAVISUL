# Static site for Railway: Caddy serves the files on $PORT.
FROM caddy:2-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY . /srv
RUN rm -f /srv/Dockerfile /srv/Caddyfile /srv/.dockerignore
