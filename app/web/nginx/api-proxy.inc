location ~ ^/(dev|test|perf|staging|production)/api(?:/|$) {
    client_max_body_size 32k;

    proxy_http_version 1.1;
    proxy_connect_timeout 2s;
    proxy_read_timeout 15s;

    proxy_set_header Connection "";
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Request-ID $request_id;

    proxy_pass http://api:8000;
}
