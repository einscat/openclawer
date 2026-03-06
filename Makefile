UNAME_S := $(shell uname -s)

up:
ifeq ($(UNAME_S),Darwin)
	docker compose --env-file .env up -d --remove-orphans --force-recreate
else
	docker compose --env-file .env up -d --remove-orphans
endif

down:
ifeq ($(UNAME_S),Darwin)
	docker compose --env-file .env down --remove-orphans
else
	docker compose --env-file .env down
endif

devices:
	docker exec -it app-openclaw-gateway openclaw devices list

# 1. 在外部定义变量
REQUEST_ID_CLEAN = $(shell docker exec app-openclaw-gateway openclaw devices list | \
    sed -r "s/\x1B\[([0-9]{1,3}(;[0-9]{1,2})?)?[mGK]//g" | \
    awk -F '│' '/[0-9a-f]{8}-/ {print $$2; exit}' | \
    tr -d ' ')

approve:
	@echo "Request ID 是：$(REQUEST_ID_CLEAN)"
	docker exec -it app-openclaw-gateway openclaw devices approve $(REQUEST_ID_CLEAN)