#!/bin/bash
# pansou-to-xiaoya.sh - pansou 分享链接转存到 xiaoya（通过 g-box API）
# 用法: bash pansou-to-xiaoya.sh "分享URL" "保存路径" "网盘类型"
# 示例: bash pansou-to-xiaoya.sh "https://pan.quark.cn/s/aa8e5a837bb9" "/🍊我的夸克分享/电影/疯狂的石头" "quark"

set -e

SHARE_URL="$1"
SAVE_PATH="$2"
DISK_TYPE="$3"

# 配置
GBOX_URL="${GBOX_URL:-http://YOUR_TAILSCALE_IP:4567}"
GBOX_USER="${GBOX_USER:-admin}"
GBOX_PASS="${GBOX_PASS:-admin}"

# 网盘类型映射
case "$DISK_TYPE" in
    "quark"|"夸克"|"🍒")
        TYPE=5
        ;;
    "115"|"🥝")
        TYPE=4
        ;;
    "aliyun"|"阿里"|"阿里云盘"|"🍉")
        TYPE=0
        ;;
    "uc"|"UC"|"🍓")
        TYPE=7
        ;;
    *)
        echo "❌ 不支持的网盘类型: $DISK_TYPE"
        echo "支持: quark/夸克/🍒, 115/🥝, aliyun/阿里/阿里云盘/🍉, uc/UC/🍓"
        exit 1
        ;;
esac

# 从 URL 提取 share_id
# 格式: https://pan.quark.cn/s/xxx 或 https://www.aliyundrive.com/s/xxx
SHARE_ID=$(echo "$SHARE_URL" | grep -oE '/s/[a-zA-Z0-9]+' | sed 's#/s/##')

if [ -z "$SHARE_ID" ]; then
    echo "❌ 无法从 URL 提取 share_id: $SHARE_URL"
    exit 1
fi

echo "📌 share_id: $SHARE_ID"
echo "📌 save_path: $SAVE_PATH"
echo "📌 disk_type: $TYPE"

# 登录 g-box API 获取 token
echo "🔐 登录 g-box..."
TOKEN=$(curl -s --max-time 10 "$GBOX_URL/api/accounts/login" \
    -X POST \
    -H 'Content-Type: application/json' \
    -d "{\"username\":\"$GBOX_USER\",\"password\":\"$GBOX_PASS\"}" \
    | jq -r '.token')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo "❌ g-box 登录失败"
    exit 1
fi

echo "✅ 登录成功"

# 添加分享到 g-box
echo "📤 添加分享到 g-box..."
RESULT=$(curl -s --max-time 30 "$GBOX_URL/api/shares" \
    -X POST \
    -H 'Content-Type: application/json' \
    -H "X-ACCESS-TOKEN: $TOKEN" \
    -d "{\"path\":\"$SAVE_PATH\",\"shareId\":\"$SHARE_ID\",\"type\":$TYPE,\"folderId\":\"0\",\"temp\":false}")

# 解析结果
SHARE_DB_ID=$(echo "$RESULT" | jq -r '.id')

if [ -z "$SHARE_DB_ID" ] || [ "$SHARE_DB_ID" = "null" ]; then
    echo "❌ 添加失败: $RESULT"
    exit 1
fi

echo "✅ 添加成功！share_id=$SHARE_DB_ID"

# 验证资源是否出现在 xiaoya
echo "🔍 验证资源..."
XIAOYA_URL="${XIAOYA_URL:-http://YOUR_TAILSCALE_IP:5678}"

# 等待 2 秒让 g-box 同步
sleep 2

# 检查路径是否存在
CHECK=$(curl -s --max-time 10 "$XIAOYA_URL/api/fs/list" \
    -X POST \
    -H 'Content-Type: application/json' \
    -d "{\"path\":\"$SAVE_PATH\",\"page\":1,\"per_page\":5}" \
    | jq -r '.data.total')

if [ "$CHECK" = "null" ] || [ -z "$CHECK" ]; then
    echo "⚠️ 资源可能需要稍等片刻才能访问"
else
    echo "✅ 资源已就绪，共 $CHECK 个文件"
fi

# 输出结果供后续使用
echo ""
echo "=== 转存完成 ==="
echo "xiaoya_path: $SAVE_PATH"
echo "share_db_id: $SHARE_DB_ID"
echo "share_url_id: $SHARE_ID"
