#!/usr/bin/env sh
set -e

echo "Fixing directory permissions..."  # 正在修复目录权限...
chown -R node:node /home/node/.openclaw
echo "Applying configurations as node user..."  # 以 node 用户身份应用配置...

# 创建临时执行脚本（heredoc 用单引号，内部几乎不用转义）
cat > /tmp/init-openclaw-node.sh <<'EOT'
#!/usr/bin/env sh
set -e

# 优先使用环境变量，没有则尝试从 secrets 读取
export OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$(cat /run/secrets/openclaw_gateway_token 2>/dev/null || true)}"

# 设置认证模式为 token（强烈推荐）
node dist/index.js config set gateway.auth.mode token
node dist/index.js config set gateway.auth.token "${OPENCLAW_GATEWAY_TOKEN}"

# 如果 secrets 或 env 都没提供 token，生成一个随机强 token 并打印到日志（方便查看）
if [ -z "${OPENCLAW_GATEWAY_TOKEN}" ]; then
  NEW_TOKEN=$(head -c 48 /dev/urandom | base64 | tr -d "\n")
  node dist/index.js config set gateway.auth.token "${NEW_TOKEN}"
  # 【警告】未提供 token，已自动生成随机强 token（请务必保存！）
  echo "WARNING: No token provided in secrets or env. Generated random strong token (save this!): ${NEW_TOKEN}"
fi

if [ "${OPENCLAW_DOMAIN_ENABLE:-false}" = "true" ]; then
  node dist/index.js config set gateway.bind loopback
else
  node dist/index.js config set gateway.bind lan
fi

# 其他推荐的安全配置（推荐 loopback，避免安全错误）
node dist/index.js config set gateway.mode local
node dist/index.js config set agents.defaults.sandbox.mode off

# 关闭危险的调试开关（生产环境不建议开启）
node dist/index.js config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback false
node dist/index.js config set gateway.controlUi.allowInsecureAuth false
node dist/index.js config set gateway.controlUi.dangerouslyDisableDeviceAuth false

# 解决错误：Gateway failed to start: Error: non-loopback Control UI requires gateway.controlUi.allowedOrigins (set explicit origins), or set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback=true to use Host-header origin fallback mode
# 关键修改：直接用 ${VAR}，CLI 会正确解析 JSON 字符串
# 默认值也写成合法 JSON 字符串（不带外层单引号）
echo $OPENCLAW_ALLOWED_ORIGINS
node dist/index.js config set gateway.controlUi.allowedOrigins "${OPENCLAW_ALLOWED_ORIGINS:-"[ \"http://127.0.0.1:18789\", \"https://127.0.0.1:18789\", \"http://localhost:18789\", \"https://localhost:18789\" ]"}"

node dist/index.js config set gateway.trustedProxies "[ \"172.20.0.0/24\" ]"

echo "Init complete"  # 配置应用完成。
EOT

chmod +x /tmp/init-openclaw-node.sh

# 以 node 用户执行临时脚本
su node -c "/tmp/init-openclaw-node.sh"

# 清理临时文件（可选）
rm -f /tmp/init-openclaw-node.sh
