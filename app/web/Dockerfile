# syntax=docker/dockerfile:1.7

FROM nginxinc/nginx-unprivileged:1.30.3-alpine

COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY src/ /usr/share/nginx/html/

USER 101:101

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["wget", "-q", "-T", "2", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]
