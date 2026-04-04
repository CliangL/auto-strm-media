#!/bin/bash
# moontv 资源搜索转 STRM 脚本
# 用法: bash moontv-to-strm.sh "关键词" [源]
# 示例: bash moontv-to-strm.sh "白夜追凶"
#        bash moontv-to-strm.sh "白夜追凶" "dbzy.tv"

KEYWORD="$1"
SOURCE="$2"
MOONTV_BASE="${MOONTV_BASE:-https://YOUR_DOMAIN}"
COOKIE_FILE="/tmp/moontv_cookie.txt"

# 获取可用源列表
get_sources() {
    curl -s --max-time 10 -b "$COOKIE_FILE" "${MOONTV_BASE}/api/sources" 2>/dev/null
}

# 搜索单个源
search_source() {
    local src="$1"
    local kw="$2"
    curl -s --max-time 20 -b "$COOKIE_FILE" \
        "${MOONTV_BASE}/api/source-test?q=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$kw'))")&source=${src}" 2>/dev/null
}

# 解析结果并输出
parse_results() {
    local json="$1"
    local src_name="$2"
    
    # 检查是否成功
    success=$(echo "$json" | jq -r '.success' 2>/dev/null)
    if [ "$success" != "true" ]; then
        return
    fi
    
    # 检查结果数
    count=$(echo "$json" | jq -r '.resultCount' 2>/dev/null)
    if [ "$count" -eq 0 ] || [ "$count" = "null" ]; then
        return
    fi
    
    # 解析每个结果
    results=$(echo "$json" | jq -r '.results[]' 2>/dev/null)
    while IFS= read -r result; do
        [ -z "$result" ] && continue
        
        # 提取基本信息
        title=$(echo "$result" | jq -r '.vod_name' 2>/dev/null)
        remarks=$(echo "$result" | jq -r '.vod_remarks // empty' 2>/dev/null)
        play_url=$(echo "$result" | jq -r '.vod_play_url // empty' 2>/dev/null)
        
        [ -z "$title" ] || [ "$title" = "null" ] && continue
        [ -z "$play_url" ] || [ "$play_url" = "null" ] && continue
        
        # 提取集数信息（从 vod_play_url 中）
        echo "$result" | jq -r --arg src "$src_name" --arg title "$title" --arg remarks "$remarks" '
            .vod_play_url | split("$$$") | .[0] | split("#") | .[] | 
            split("$")[0] as $ep_name |
            split("$")[1] as $url |
            if $url != null and ($url | test("\\.m3u8")) then
                "\($src_name)|\($title)|\($ep_name)|\($url)"
            else
                empty
            end
        ' 2>/dev/null
    done <<< "$results"
}

# 搜索所有源
search_all() {
    local kw="$1"
    local sources_json=$(get_sources)
    
    # 获取所有源
    keys=$(echo "$sources_json" | jq -r '.[].key' 2>/dev/null)
    
    for src in $keys; do
        src_name=$(echo "$sources_json" | jq -r ".[] | select(.key==\"$src\") | .name" 2>/dev/null)
        echo "=== 搜索 $src_name ($src) ===" >&2
        
        result=$(search_source "$src" "$kw")
        parse_results "$result" "$src_name"
    done
}

# 主流程
if [ -z "$KEYWORD" ]; then
    echo "用法: bash moontv-to-strm.sh \"关键词\" [源]"
    echo "  示例: bash moontv-to-strm.sh \"白夜追凶\""
    exit 1
fi

# 确保 cookie 有效
if [ ! -f "$COOKIE_FILE" ] || ! grep -q "YOUR_DOMAIN" "$COOKIE_FILE" 2>/dev/null; then
    curl -s --max-time 10 -c "$COOKIE_FILE" -X POST "${MOONTV_BASE}/api/login" \
        -H "Content-Type: application/json" \
        -d '{"username":"YOUR_USERNAME","password":"YOUR_PASSWORD"}' > /dev/null
fi

if [ -n "$SOURCE" ]; then
    # 搜索指定源
    result=$(search_source "$SOURCE" "$KEYWORD")
    parse_results "$result" "$SOURCE"
else
    # 搜索所有源
    search_all "$KEYWORD"
fi
