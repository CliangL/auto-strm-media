#!/bin/bash
# 影视搜索脚本 v2.6
# 流程：xiaoya 本地索引(快速) → pansou API → moontv 资源站
# 修复：跳过失效的 xiaoya API 验证，直接用 pansou
# 用法: bash search-media.sh "关键词"

KEYWORD="$1"
INDEX="/Users/cliang/.openclaw/workspace/data/media-index.txt"
XIAOYA_BASE="${XIAOYA_BASE:-http://YOUR_TAILSCALE_IP:5678/d}"
XIAOYA_API="${XIAOYA_API:-http://YOUR_TAILSCALE_IP:5678/api/fs/list}"
PANSOU_API="${PANSOU_API:-http://YOUR_TAILSCALE_IP:8080/api/search}"
MOONTV_BASE="${MOONTV_BASE:-https://YOUR_DOMAIN}"
MOONTV_COOKIE="/tmp/moontv_cookie.txt"

if [ -z "$KEYWORD" ]; then
    echo "用法: bash search-media.sh '关键词'"
    exit 1
fi

# ============================================
# Step 1: xiaoya 本地索引（快速检查，跳过慢验证）
# ============================================
RESULTS=$(grep -i "$KEYWORD" "$INDEX" 2>/dev/null | sort -u | head -30)
TOTAL=$(echo "$RESULTS" | grep -c . 2>/dev/null) || TOTAL=0

# 直接输出本地索引结果（不验证），让用户自己判断
if [ -n "$TOTAL" ] && [ "$TOTAL" -gt 0 ] 2>/dev/null; then
    # 先按质量排序
    SORTED=$(echo "$RESULTS" | awk -F'#' '{
        score=0
        if ($0 ~ /4[Kk]|2160[pP]/) score+=100
        if ($0 ~ /REMUX|Remux/) score+=50
        if ($0 ~ /[Bb]lu[Rr]ay/) score+=40
        if ($0 ~ /1080[pP]/) score+=30
        if ($0 ~ /[Hh][Ee][Vv][Cc]|x265/) score+=20
        if ($0 ~ /10bit/) score+=10
        if ($0 ~ /HDTV/) score-=10
        if ($0 ~ /DVDRip/) score-=20
        print score "\t" $0
    }' | sort -rn | head -10)
    
    echo "XIAOYA|$TOTAL"
    
    # 使用临时文件避免管道问题
    TMPFILE=$(mktemp)
    echo "$SORTED" > "$TMPFILE"
    
    while IFS=$'\t' read -r score line; do
        [ -z "$line" ] && continue
        PATH_PART=$(echo "$line" | cut -d'#' -f1 | sed 's/^\.\///')
        NAME=$(echo "$line" | cut -d'#' -f2)
        RATING=$(echo "$line" | cut -d'#' -f4)
        YEAR=$(echo "$line" | cut -d'#' -f6)
        
        # 如果 NAME 为空，从路径提取
        if [ -z "$NAME" ] || [ "$NAME" = "" ]; then
            NAME=$(basename "$PATH_PART")
        fi
        
        # 提取清晰度和来源
        QUALITY="SD"
        echo "$PATH_PART" | grep -qi '4k\|2160p' && QUALITY="4K"
        echo "$PATH_PART" | grep -qi '1080p' && QUALITY="1080p"
        echo "$PATH_PART" | grep -qi '720p' && QUALITY="720p"
        echo "$PATH_PART" | grep -qi 'remux' && QUALITY="$QUALITY REMUX"
        echo "$PATH_PART" | grep -qi 'bluray\|blu-ray' && QUALITY="$QUALITY 蓝光"
        echo "$PATH_PART" | grep -qi 'hevc\|x265' && QUALITY="$QUALITY HEVC"
        
        SOURCE="xiaoya"
        echo "$PATH_PART" | grep -qi '115' && SOURCE="115网盘"
        echo "$PATH_PART" | grep -qi 'pikpak' && SOURCE="PikPak"
        echo "$PATH_PART" | grep -qi 'quark' && SOURCE="夸克"
        
        ENCODED=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$PATH_PART" 2>/dev/null)
        URL="${XIAOYA_BASE}/${ENCODED}"
        
        # 直接输出，不验证（索引可能过期）
        echo "AVAIL|?|$QUALITY|$SOURCE|$NAME|$RATING|$YEAR|$URL|?"
    done < "$TMPFILE"
    
    rm -f "$TMPFILE"
fi

# ============================================
# Step 2: pansou API 搜索（主要搜索源）
# ============================================
ENCODED_KEYWORD=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$KEYWORD")
PANSOU_JSON=$(curl -s "${PANSOU_API}?kw=${ENCODED_KEYWORD}&res=merge" --max-time 15 2>/dev/null)

if [ -n "$PANSOU_JSON" ]; then
    CODE=$(echo "$PANSOU_JSON" | jq -r '.code' 2>/dev/null)
    if [ "$CODE" = "0" ]; then
        TOTAL_PANSOU=0
        for TYPE in quark aliyun uc 115 baidu xunlei; do
            COUNT=$(echo "$PANSOU_JSON" | jq ".data.merged_by_type.$TYPE | length" 2>/dev/null)
            if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ] 2>/dev/null; then
                TOTAL_PANSOU=$((TOTAL_PANSOU + COUNT))
            fi
        done
        
        if [ "$TOTAL_PANSOU" -gt 0 ] 2>/dev/null; then
            echo "PANSOU|$TOTAL_PANSOU"
            
            for TYPE in quark 115 aliyun uc; do
                COUNT=$(echo "$PANSOU_JSON" | jq ".data.merged_by_type.$TYPE | length" 2>/dev/null)
                if [ -n "$COUNT" ] && [ "$COUNT" -gt 0 ] 2>/dev/null; then
                    for i in $(seq 0 $((COUNT - 1)) | head -10); do
                        URL=$(echo "$PANSOU_JSON" | jq -r ".data.merged_by_type.$TYPE[$i].url" 2>/dev/null)
                        PASSWORD=$(echo "$PANSOU_JSON" | jq -r ".data.merged_by_type.$TYPE[$i].pwd" 2>/dev/null)
                        NOTE=$(echo "$PANSOU_JSON" | jq -r ".data.merged_by_type.$TYPE[$i].note" 2>/dev/null)
                        DATETIME=$(echo "$PANSOU_JSON" | jq -r ".data.merged_by_type.$TYPE[$i].datetime" 2>/dev/null)
                        
                        TYPE_LABEL="$TYPE"
                        [ "$TYPE" = "quark" ] && TYPE_LABEL="夸克"
                        [ "$TYPE" = "115" ] && TYPE_LABEL="115网盘"
                        [ "$TYPE" = "aliyun" ] && TYPE_LABEL="阿里云盘"
                        [ "$TYPE" = "uc" ] && TYPE_LABEL="UC网盘"
                        
                        echo "PANSOU_ITEM|$TYPE_LABEL|$URL|$PASSWORD|$NOTE|$DATETIME"
                    done
                fi
            done
        fi
    fi
fi

# ============================================
# Step 3: moontv 资源站（备用）
# ============================================

# 确保 moontv cookie 有效
ensure_moontv_login() {
    if [ ! -f "$MOONTV_COOKIE" ] || ! grep -q "YOUR_DOMAIN" "$MOONTV_COOKIE" 2>/dev/null; then
        curl -s --max-time 10 -c "$MOONTV_COOKIE" -X POST "${MOONTV_BASE}/api/login" \
            -H "Content-Type: application/json" \
            -d '{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD"}' > /dev/null 2>&1
    fi
}

search_moontv_source() {
    local src="$1"
    local kw="$2"
    curl -s --max-time 15 -b "$MOONTV_COOKIE" \
        "${MOONTV_BASE}/api/source-test?q=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$kw'))")&source=${src}" 2>/dev/null
}

ensure_moontv_login

# 获取所有源
SOURCES_JSON=$(curl -s --max-time 10 -b "$MOONTV_COOKIE" "${MOONTV_BASE}/api/sources" 2>/dev/null)
TOTAL_MOONTV=0

while IFS= read -r src_line; do
    [ -z "$src_line" ] && continue
    src_key=$(echo "$src_line" | jq -r '.key' 2>/dev/null)
    src_name=$(echo "$src_line" | jq -r '.name' 2>/dev/null)
    
    # 跳过成人资源站
    echo "$src_name" | grep -q "🔞" && continue
    [ -z "$src_key" ] || [ "$src_key" = "null" ] && continue
    
    result=$(search_moontv_source "$src_key" "$KEYWORD" 2>/dev/null)
    count=$(echo "$result" | jq -r '.resultCount // 0' 2>/dev/null)
    
    if [ -n "$count" ] && [ "$count" -gt 0 ] && [ "$count" != "null" ] 2>/dev/null; then
        TOTAL_MOONTV=$((TOTAL_MOONTV + count))
        
        while IFS= read -r item_json; do
            [ -z "$item_json" ] && continue
            
            title=$(echo "$item_json" | jq -r '.vod_name' 2>/dev/null)
            remarks=$(echo "$item_json" | jq -r '.vod_remarks // ""' 2>/dev/null)
            year=$(echo "$item_json" | jq -r '.vod_year // ""' 2>/dev/null)
            play_url=$(echo "$item_json" | jq -r '.vod_play_url // ""' 2>/dev/null)
            
            [ -z "$title" ] || [ "$title" = "null" ] && continue
            [ -z "$play_url" ] || [ "$play_url" = "null" ] || [ "$play_url" = "" ] && continue
            
            echo "MOONTV_ITEM|$src_name|$title|$remarks|$year|$src_key|$play_url"
            
        done < <(echo "$result" | jq -r '.results[] | select(.vod_play_url != null and .vod_play_url != "") | @json' 2>/dev/null)
    fi
done < <(echo "$SOURCES_JSON" | jq -r '.[]' 2>/dev/null)

if [ "$TOTAL_MOONTV" -gt 0 ] 2>/dev/null; then
    echo "MOONTV|$TOTAL_MOONTV"
fi

exit 0
