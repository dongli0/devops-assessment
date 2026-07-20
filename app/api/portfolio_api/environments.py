from enum import StrEnum


class Environment(StrEnum):
    DEV = "dev"
    TEST = "test"
    PERF = "perf"
    STAGING = "staging"
    PRODUCTION = "production"
