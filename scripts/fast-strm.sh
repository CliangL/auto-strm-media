#!/bin/bash
# fast-strm.sh - 快速 STRM 创建（优化版）
# 用法: bash fast-strm.sh "剧名" "分享URL" "保存路径" "网盘类型"
# 示例: bash fast-strm.sh "危险关系" "https://pan.quark.cn/s/xxx" "/🍊我的夸克分享/电视剧/剧名" "quark"

set -e

NAME="$1"
SHARE_URL="$2"
SAVE_PATH="$3"
DISK_TYPE="$4"

# 配置
GBOX_URL="${GBOX_URL:-http://YOUR_TAILSCALE_IP:4567}"
# STRM URL 使用局域网 IP（播放用）
XIAOYA_URL="${XIAOYA_URL:-http://YOUR_LAN_IP:5678/d}"
# API 使用 Tailscale IP（监控用）
XIAOYA_API="${XIAOYA_API:-http://YOUR_TAILSCALE_IP:5678/api/fs}"
NAS_SSH="sshpass -p 'YOUR_PASSWORD' ssh -o StrictHostKeyChecking=no YOUR_USERNAME@YOUR_TAILSCALE_IP"
STRM_BASE="/vol1/docker/xiaoya/strm/C-每日更新/电视剧"

# 网盘类型映射
case "$DISK_TYPE" in
    "quark"|"夸克") TYPE=5 ;;
    "115") TYPE=4 ;;
    "aliyun"|"阿里") TYPE=0 ;;
    "uc"|"UC") TYPE=7 ;;
    *) echo "❌ 不支持: $DISK_TYPE"; exit 1 ;;
esac

# 提取 share_id
SHARE_ID=$(echo "$SHARE_URL" | grep -oE '/s/[a-zA-Z0-9]+' | sed 's#/s/##')
[ -z "$SHARE_ID" ] && { echo "❌ 无法提取 share_id"; exit 1; }

echo "🚀 快速流程开始..."

# ============================================
# Step 1: 登录 + 添加分享（并行准备）
# ============================================
TOKEN=$(curl -s --max-time 5 "$GBOX_URL/api/accounts/login" \
    -X POST -H 'Content-Type: application/json' \
    -d '{"username":"admin","password":"admin"}' | jq -r '.token')

[ -z "$TOKEN" ] && { echo "❌ 登录失败"; exit 1; }

# 添加分享（不等待验证）
curl -s --max-time 10 "$GBOX_URL/api/shares" \
    -X POST -H 'Content-Type: application/json' \
    -H "X-ACCESS-TOKEN: $TOKEN" \
    -d "{\"path\":\"$SAVE_PATH\",\"shareId\":\"$SHARE_ID\",\"type\":$TYPE,\"folderId\":\"0\",\"temp\":false}" \
    | jq -r '.id' > /tmp/share_id.txt

echo "✅ 转存完成"

# ============================================
# Step 2: 查文件 + TMDB（并行）
# ============================================
# 等待 1 秒让 g-box 同步
sleep 1

# 查文件结构（递归查找视频）
FILES=$(curl -s --max-time 8 "$XIAOYA_URL/../api/fs/list" \
    -X POST -H 'Content-Type: application/json' \
    -d "{\"path\":\"$SAVE_PATH\",\"page\":1,\"per_page\":100}" \
    | jq -r '.data.content[] | select(.name | test("mkv|mp4|avi")) | .name')

# 如果第一层没找到，尝试子目录
if [ -z "$FILES" ]; then
    SUBDIR=$(curl -s --max-time 8 "$XIAOYA_URL/../api/fs/list" \
        -X POST -H 'Content-Type: application/json' \
        -d "{\"path\":\"$SAVE_PATH\",\"page\":1,\"per_page\":20}" \
        | jq -r '.data.content[0].name')
    
    [ -n "$SUBDIR" ] && FILES=$(curl -s --max-time 8 "$XIAOYA_URL/../api/fs/list" \
        -X POST -H 'Content-Type: application/json' \
        -d "{\"path\":\"$SAVE_PATH/$SUBDIR\",\"page\":1,\"per_page\":100}" \
        | jq -r '.data.content[] | select(.name | test("mkv|mp4|avi")) | .name')
    
    SAVE_PATH="$SAVE_PATH/$SUBDIR"
fi

COUNT=$(echo "$FILES" | grep -c . || echo 0)
echo "📊 找到 $COUNT 个视频文件"

# TMDB 查询（后台并行）
TMDB_INFO=$(bash scripts/media-info.sh "$NAME" --max-time 5 2>/dev/null || echo "TV|$NAME|0|2026|Unknown")
TV_STATUS=$(echo "$TMDB_INFO" | grep "Returning Series" && echo "ongoing" || echo "completed")
TOTAL=$(echo "$TMDB_INFO" | grep "DETAIL" | cut -d'|' -f3 || echo "0")

# ============================================
# Step 3: 创建 STRM（单次 SSH）
# ============================================
STRM_DIR="$STRM_BASE/$NAME (2026)/Season 01"

# 构建 STRM 创建命令
STRM_CMD="mkdir -p '$STRM_DIR'; "
for FILE in $FILES; do
    # 提取集数
    EP=$(echo "$FILE" | grep -oE 'E[0-9]+|[0-9]+' | tail -1 | sed 's/E//')
    EP_NUM=$(printf "%02d" "$EP")
    
    # URL 编码
    ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$SAVE_PATH/$FILE', safe=':/'))")
    URL="$XIAOYA_URL/$ENCODED"
    
    STRM_CMD+="echo '$URL' > '$STRM_DIR/S01E$EP_NUM.strm'; "
done

# 单次 SSH 执行所有创建
$NAS_SSH "$STRM_CMD"
echo "✅ STRM 创建完成 ($COUNT 个)"

# ============================================
# Step 4: 输出结果（最后更新状态）
# ============================================
echo ""
echo "=== 完成 ==="
echo "📺 $NAME | $COUNT 集 | 状态: $TV_STATUS"
echo "🎬 播放: YOUR_EMBY_URL"

# 追剧状态（供后续更新）
if [ "$TV_STATUS" = "ongoing" ]; then
    echo "追剧: $NAME|$COUNT|$TOTAL|ongoing"
fi
