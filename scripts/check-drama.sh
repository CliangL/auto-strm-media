#!/bin/bash
# 追剧更新检查脚本 v4.1
# 监控 xiaoya 夸克网盘目录，有新视频文件就生成 STRM 并通知
# 通过 SSH 到 NAS 上创建 STRM 文件

NAS_HOST="${NAS_HOST:-YOUR_USERNAME@YOUR_TAILSCALE_IP}"
NAS_PASS="${NAS_PASS:-YOUR_PASSWORD}"
XIAOYA_BASE="${XIAOYA_BASE:-http://YOUR_LAN_IP:5678}"
XIAOYA_API="${XIAOYA_API:-http://YOUR_TAILSCALE_IP:5678/api/fs}"
STRM_BASE="/vol1/1000/docker/xiaoya/strm/C-每日更新"
STATE_FILE="/Users/cliang/.openclaw/workspace/data/drama-state.json"
TMDB_KEY="${TMDB_API_KEY:-YOUR_TMDB_API_KEY}"

mkdir -p /Users/cliang/.openclaw/workspace/data

if [ ! -f "$STATE_FILE" ]; then
    echo '{}' > "$STATE_FILE"
fi

UPDATES=""
NEW_EPISODES=""

# ============================================
# 辅助函数：获取 xiaoya 目录下的视频文件列表
# ============================================
get_xiaoya_files() {
    local path="$1"
    ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$path'))")
    curl -s --max-time 10 "${XIAOYA_API}/list?path=/${ENCODED}" 2>/dev/null | \
        jq -r '.data.content[]? | select(.name | test("\\.(mkv|mp4|ts|avi)$")) | .name' 2>/dev/null
}

# ============================================
# 辅助函数：生成单个视频的 STRM 文件（通过 SSH 到 NAS）
# ============================================
generate_strm() {
    local video_path="$1"
    local video_name="$2"
    local season_dir="$3"
    local strm_name="$4"
    
    # 生成 STRM URL
    ENCODED_PATH=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$video_path'))")
    STRM_URL="${XIAOYA_BASE}/d/${ENCODED_PATH}"
    
    # SSH 到 NAS 创建目录和 STRM 文件
    sshpass -p "$NAS_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$NAS_HOST" \
        "mkdir -p '$season_dir' && echo '$STRM_URL' > '$season_dir/${strm_name}.strm'" 2>/dev/null
    
    echo "CREATED|${strm_name}.strm"
}

# ============================================
# 辅助函数：从文件名提取集数
# ============================================
extract_episode() {
    local filename="$1"
    # 匹配 S01E01, E01, 第01集 等格式
    echo "$filename" | grep -oE '[Ss]01[Ee][0-9]+|[Ee][0-9]+|第[0-9]+集' | head -1 | sed 's/^[Ss]01//'
}

# ============================================
# 主流程：检查每个追剧
# ============================================
DRAMAS=$(jq -r 'to_entries[] | select(.value.status == "ongoing") | .key' "$STATE_FILE" 2>/dev/null)

for DRAMA in $DRAMAS; do
    [ -z "$DRAMA" ] && continue
    
    # 获取追剧配置
    XIAOYA_PATH=$(jq -r --arg d "$DRAMA" '.[$d].xiaoya_path // empty' "$STATE_FILE" 2>/dev/null)
    
    if [ -z "$XIAOYA_PATH" ] || [ "$XIAOYA_PATH" = "null" ] || [ "$XIAOYA_PATH" = "empty" ]; then
        echo "⚠️ ${DRAMA}: 未配置 xiaoya 路径，跳过" >&2
        continue
    fi
    
    # 获取当前 xiaoya 目录下的所有视频文件
    CURRENT_FILES=$(get_xiaoya_files "$XIAOYA_PATH")
    
    if [ -z "$CURRENT_FILES" ]; then
        echo "⚠️ ${DRAMA}: xiaoya 路径无法访问: $XIAOYA_PATH" >&2
        continue
    fi
    
    # 转成数组
    readarray -t FILE_ARRAY <<< "$CURRENT_FILES"
    CURRENT_COUNT=${#FILE_ARRAY[@]}
    
    # 获取上次记录的文件列表
    LAST_FILES_JSON=$(jq -r --arg d "$DRAMA" '.[$d].last_files // []' "$STATE_FILE" 2>/dev/null)
    LAST_COUNT=$(jq -r --arg d "$DRAMA" '.[$d].file_count // 0' "$STATE_FILE" 2>/dev/null)
    
    # 判断有没有新文件
    if [ "$CURRENT_COUNT" -gt "$LAST_COUNT" ] 2>/dev/null; then
        NEW_COUNT=$((CURRENT_COUNT - LAST_COUNT))
        
        # 找出新文件（跳过前 LAST_COUNT 个）
        SEASON_DIR="${STRM_BASE}/电视剧/${DRAMA}/Season 1"
        EP_LIST=""
        
        for ((i=LAST_COUNT; i<CURRENT_COUNT; i++)); do
            video_file="${FILE_ARRAY[$i]}"
            [ -z "$video_file" ] && continue
            
            # 提取集数
            EP=$(extract_episode "$video_file")
            [ -n "$EP" ] && EP_LIST="${EP_LIST}${EP}, "
            
            # 生成 STRM 文件名
            if [[ "$video_file" =~ [Ss]01[Ee]([0-9]+) ]]; then
                strm_name="S01E${BASH_REMATCH[1]}"
            elif [[ "$video_file" =~ [Ee]([0-9]+) ]]; then
                strm_name="E${BASH_REMATCH[1]}"
            elif [[ "$video_file" =~ 第([0-9]+)集 ]]; then
                strm_name="E${BASH_REMATCH[1]}"
            else
                strm_name="${video_file%.*}"
            fi
            
            # 通过 SSH 到 NAS 创建 STRM
            generate_strm "${XIAOYA_PATH}/${video_file}" "$video_file" "$SEASON_DIR" "$strm_name"
        done
        
        UPDATES="${UPDATES}📺 ${DRAMA}: 发现 +${NEW_COUNT} 集新内容 (${EP_LIST:-新文件})\n"
        NEW_EPISODES="yes"
    fi
    
    # 更新状态（存储所有文件列表）
    FILE_LIST=$(printf '%s\n' "${FILE_ARRAY[@]}" | jq -R . | jq -s .)
    TMP=$(mktemp)
    jq --arg d "$DRAMA" \
       --argjson count "$CURRENT_COUNT" \
       --argjson files "$FILE_LIST" \
       --arg lc "$(date +%Y-%m-%d)" \
       '.[$d].file_count = $count | .[$d].last_files = $files | .[$d].last_check = $lc' \
       "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
    
    sleep 0.5
done

# 输出结果
if [ "$NEW_EPISODES" = "yes" ]; then
    echo "NEW_EPISODES_FOUND"
    echo -e "$UPDATES"
    echo "请到 Emby 或飞牛影视 查看新内容"
else
    echo "NO_UPDATES"
    echo "当前追剧的剧集没有新变化"
fi
