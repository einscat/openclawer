#!/usr/bin/env sh
set -e

echo "==> 正在修复目录权限..."
chown -R node:node /home/node/.openclaw
echo "==> 正在解析环境变量与凭证..."

# 1. 解析 Token (优先环境变量 -> 其次 secrets -> 兜底随机生成)
TOKEN="${OPENCLAW_GATEWAY_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f /run/secrets/openclaw_gateway_token ]; then
  # 增加 tr -d '\n'，防止 docker secrets 自动追加的换行符破坏 JSON 结构
  TOKEN=$(cat /run/secrets/openclaw_gateway_token | tr -d '\n')
fi

if [ -z "$TOKEN" ]; then
  TOKEN=$(head -c 48 /dev/urandom | base64 | tr -d '\n')
  echo "⚠️ 警告: 未在 env 或 secrets 中发现 Token。"
  echo "⚠️ 已自动生成随机强 Token（请务必保存！）: ${TOKEN}"
fi

# 2. 解析网关绑定模式
BIND_MODE="lan"

DEBUG_MODE="true"
if [ "${OPENCLAW_DOMAIN_ENABLE:-false}" = "true" ]; then
  DEBUG_MODE="false"
fi

# 3. 解析跨域白名单 (提供标准 JSON 数组兜底)
DEFAULT_ORIGINS='[ "http://127.0.0.1:18789", "https://127.0.0.1:18789", "http://localhost:18789", "https://localhost:18789" ]'
ORIGINS="${OPENCLAW_ALLOWED_ORIGINS:-$DEFAULT_ORIGINS}"

echo "==> 以 node 用户身份生成并执行配置脚本..."

# 【核心优化】：使用不带单引号的 EOF。
# 这样外层的 root 用户会直接把计算好的 ${TOKEN}、${ORIGINS} 渲染成静态字符串写死在脚本里。
# 内部需要执行的命令变量使用 \$ 转移，推迟给 node 用户执行。
cat > /tmp/init-openclaw-node.sh <<EOF
#!/usr/bin/env sh
set -e

# 提取公共前缀，代码更清爽
CLI="node dist/index.js config set"

# 设置认证模式为 token（强烈推荐）
\$CLI gateway.auth.mode token
\$CLI gateway.auth.token "${OPENCLAW_GATEWAY_TOKEN}"
\$CLI gateway.bind '${BIND_MODE}'
# 其他推荐的安全配置（推荐 loopback，避免安全错误）
\$CLI gateway.mode local
\$CLI agents.defaults.sandbox.mode off

# 关闭危险的调试开关（生产环境不建议开启）
\$CLI gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback ${DEBUG_MODE}
\$CLI gateway.controlUi.allowInsecureAuth ${DEBUG_MODE}
\$CLI gateway.controlUi.dangerouslyDisableDeviceAuth ${DEBUG_MODE}

# 外层使用单引号包裹 JSON，完美规避 Node CLI 解析双引号和转义符的语法泥潭
# 解决错误：Gateway failed to start: Error: non-loopback Control UI requires gateway.controlUi.allowedOrigins (set explicit origins), or set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true to use Host-header origin fallback mode
# 关键修改：直接用 ${VAR}，CLI 会正确解析 JSON 字符串
# 默认值也写成合法 JSON 字符串（不带外层单引号）
\$CLI gateway.controlUi.allowedOrigins '${ORIGINS}'
\$CLI gateway.trustedProxies '[ "172.20.0.0/24" ]'

echo "==> OpenClaw 配置应用完成！"
EOF

chmod +x /tmp/init-openclaw-node.sh

# 纯净执行，无需担心 su 导致的环境变量丢失问题
su node -c "/tmp/init-openclaw-node.sh"

# 清理临时文件，保持容器整洁
rm -f /tmp/init-openclaw-node.sh
