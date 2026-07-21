location ~ ^/(dev|test|perf|staging|production)/api(?:/|$) {
    return 404;
}
