UNAME_S := $(shell uname -s)

make openssl:
	openssl rand -hex 32

# 生成 64 位十六进制 token 并写入 .env
token:
	@echo "正在生成新的 OPENCLAW_GATEWAY_TOKEN..."
	@openssl rand -hex 32 | { read token; \
		if grep -q "^OPENCLAW_GATEWAY_TOKEN=" .env 2>/dev/null; then \
			sed -i '' "s|^OPENCLAW_GATEWAY_TOKEN=.*|OPENCLAW_GATEWAY_TOKEN=$$token|" .env; \
		else \
			echo "OPENCLAW_GATEWAY_TOKEN=$$token" >> .env; \
		fi; \
		echo "已写入 OPENCLAW_GATEWAY_TOKEN=$$token"; \
	}

pull:
	docker compose --env-file .env pull

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

config:
	docker exec -it app-openclaw-gateway openclaw config

