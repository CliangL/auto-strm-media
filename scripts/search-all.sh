#!/bin/bash
# 全通道影视搜索 v4.1
# 串行搜索：xiaoya → pansou → CMS API（逐级降级，不浪费时间）
# 用法: bash search-all.sh "关键词"

KEYWORD="$1"
TMPDIR="/tmp/search-all-$$"
mkdir -p "$TMPDIR"

if [ -z "$KEYWORD" ]; then
    echo "用法: bash search-all.sh '关键词'"
    exit 1
fi

ENCODED_KW=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$KEYWORD")
XIAOYA_BASE="${XIAOYA_BASE:-http://YOUR_TAILSCALE_IP:5678/d}"
INDEX="/Users/cliang/.openclaw/workspace/data/media-index.txt"

# ============================================
# 通道 1: xiaoya 本地索引（最优先，2秒）
# ============================================
echo "🔍 搜索中 [1/3] xiaoya本地索引..." >&2

RESULTS=$(grep -i "$KEYWORD" "$INDEX" 2>/dev/null | sort -u | head -50)
TOTAL=$(echo "$RESULTS" | grep -c . 2>/dev/null || echo 0)
TOTAL=$((TOTAL + 0))

XIAOYA_OK=0
if [ "$TOTAL" -gt 0 ]; then
    SORTED=$(echo "$RESULTS" | awk -F'#' '{
        score=0
        if ($0 ~ /4[Kk]|2160[pP]/) score+=100
        if ($0 ~ /REMUX|Remux/) score+=50
        if ($0 ~ /[Bb]lu[Rr]ay/) score+=40
        if ($0 ~ /1080[pP]/) score+=30
        if ($0 ~ /[Hh][Ee][Vv][Cc]|x265/) score+=20
        if ($0 ~ /10bit/) score+=10
        print score "\t" $0
    }' | sort -rn | head -15)
    
    echo "$SORTED" | while IFS=$'\t' read -r score line; do
        [ -z "$line" ] && continue
        PATH_PART=$(echo "$line" | cut -d'#' -f1 | sed 's/^\.\///')
        NAME=$(echo "$line" | cut -d'#' -f2)
        RATING=$(echo "$line" | cut -d'#' -f4)
        YEAR=$(echo "$line" | cut -d'#' -f6)
        
        ENCODED=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$PATH_PART")
        URL="${XIAOYA_BASE}/${ENCODED}"
        
        HTTP=$(curl -s --max-time 8 -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null)
        if [ "$HTTP" = "200" ] || [ "$HTTP" = "302" ]; then
            QUALITY="SD"
            echo "$PATH_PART" | grep -qi '4k\|2160p' && QUALITY="4K"
            echo "$PATH_PART" | grep -qi '1080p' && QUALITY="1080p"
            echo "$PATH_PART" | grep -qi '720p' && QUALITY="720p"
            echo "$PATH_PART" | grep -qi 'remux' && QUALITY="$QUALITY REMUX"
            echo "$PATH_PART" | grep -qi 'bluray\|blu-ray' && QUALITY="$QUALITY 蓝光"
            
            SOURCE="xiaoya"
            echo "$PATH_PART" | grep -qi '115' && SOURCE="115网盘"
            echo "$PATH_PART" | grep -qi 'pikpak' && SOURCE="PikPak"
            echo "$PATH_PART" | grep -qi 'quark' && SOURCE="夸克"
            
            echo "AVAIL|$score|$QUALITY|$SOURCE|$NAME|$RATING|$YEAR|xiaoya|$URL"
        fi
    done > "$TMPDIR/xiaoya_results"
    
    XIAOYA_OK=$(grep -c '^AVAIL' "$TMPDIR/xiaoya_results" 2>/dev/null || echo 0)
    XIAOYA_OK=$((XIAOYA_OK + 0))
fi

if [ "$XIAOYA_OK" -gt 0 ]; then
    echo "SEARCH_SUMMARY|$XIAOYA_OK|0|0|xiaoya"
    cat "$TMPDIR/xiaoya_results"
    rm -rf "$TMPDIR"
    exit 0
fi

# ============================================
# 通道 2: pansou API（3秒）
# ============================================
echo "🔍 搜索中 [2/3] pansou网盘搜索..." >&2

PANSOU_API="${PANSOU_API:-http://YOUR_TAILSCALE_IP:8080/api/search}"
PANSOU_JSON=$(curl -s "${PANSOU_API}?kw=${ENCODED_KW}&res=merge" --max-time 15 2>/dev/null)

PANSOU_OK=0
if [ -n "$PANSOU_JSON" ]; then
    for TYPE in quark 115 aliyun uc; do
        COUNT=$(echo "$PANSOU_JSON" | jq ".data.merged_by_type.$TYPE | length" 2>/dev/null)
        if [ "$COUNT" -gt 0 ] 2>/dev/null; then
            for i in $(seq 0 $((COUNT - 1)) | head -5); do
                URL=$(echo "$PANSOU_JSON" | jq -r ".data.merged_by_type.$TYPE[$i].url" 2>/dev/null)
                PASSWORD=$(echo "$PANSOU_JSON" | jq -r ".data.merged_by_type.$TYPE[$i].password" 2>/dev/null)
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
    done > "$TMPDIR/pansou_results"
    
    PANSOU_OK=$(wc -l < "$TMPDIR/pansou_results" 2>/dev/null || echo 0)
    PANSOU_OK=$((PANSOU_OK + 0))
fi

if [ "$PANSOU_OK" -gt 0 ]; then
    echo "SEARCH_SUMMARY|0|$PANSOU_OK|0|pansou"
    cat "$TMPDIR/pansou_results"
    rm -rf "$TMPDIR"
    exit 0
fi

# ============================================
# 通道 3: CMS API（最后手段，10秒）
# ============================================
echo "🔍 搜索中 [3/3] CMS在线流媒体..." >&2

CMS_DIR="$TMPDIR/cms"
mkdir -p "$CMS_DIR"

SOURCE_LIST=(
    "https://api.ffzyapi.com/api.php/provide/vod|非凡资源"
    "https://360zyzz.com/api.php/provide/vod|360资源"
    "https://api.wujinapi.me/api.php/provide/vod|无尽资源"
    "https://bfzyapi.com/api.php/provide/vod|暴风资源"
    "https://api.zuidapi.com/api.php/provide/vod|最大资源"
    "https://api.guangsuapi.com/api.php/provide/vod|光速资源"
    "https://cj.lzcaiji.com/api.php/provide/vod|量子资源"
    "https://wolongzyw.com/api.php/provide/vod|卧龙资源"
    "https://jszyapi.com/api.php/provide/vod|极速资源"
    "https://api.ukuapi88.com/api.php/provide/vod|U酷影视"
    "https://www.hongniuzy2.com/api.php/provide/vod|红牛资源"
    "https://www.mdzyapi.com/api.php/provide/vod|魔都资源"
    "https://subocaiji.com/api.php/provide/vod|速播资源"
    "https://jinyingzy.com/api.php/provide/vod|金鹰点播"
    "https://api.maoyanapi.top/api.php/provide/vod|猫眼资源"
)

# 并行请求所有源
for entry in "${SOURCE_LIST[@]}"; do
    API=$(echo "$entry" | cut -d'|' -f1)
    NAME=$(echo "$entry" | cut -d'|' -f2)
    SAFE=$(echo "$NAME" | tr -cd 'a-zA-Z')
    
    (
        RESULT=$(curl -s --max-time 8 "${API}/?ac=detail&wd=${ENCODED_KW}" 2>/dev/null)
        TOTAL=$(echo "$RESULT" | jq -r '.total' 2>/dev/null)
        if [ "$TOTAL" -gt 0 ] 2>/dev/null; then
            echo "$RESULT" > "$CMS_DIR/${SAFE}.json"
        fi
    ) &
done
wait

# Python 汇总 + 去重
export KEYWORD
python3 -c "
import json, os, sys
from collections import defaultdict

cms_dir = '$CMS_DIR'
keyword = os.environ.get('KEYWORD', '')
all_results = []

for fname in os.listdir(cms_dir):
    if not fname.endswith('.json'):
        continue
    try:
        with open(os.path.join(cms_dir, fname)) as f:
            data = json.load(f)
    except:
        continue
    
    for item in data.get('list', []):
        vod_name = item.get('vod_name', '')
        vod_year = item.get('vod_year', '')
        vod_remarks = item.get('vod_remarks', '')
        vod_class = item.get('vod_class', '')
        type_name = item.get('type_name', '')
        
        play_from = item.get('vod_play_from', '')
        play_url = item.get('vod_play_url', '')
        
        froms = play_from.split('\$\$\$')
        url_groups = play_url.split('\$\$\$')
        
        for src, urls in zip(froms, url_groups):
            segments = urls.split('#')
            for seg in segments:
                parts = seg.split('\$')
                if len(parts) == 2:
                    label, url = parts[0], parts[1]
                    if '.m3u8' in url and url.startswith('http'):
                        all_results.append({
                            'name': vod_name,
                            'year': vod_year,
                            'remarks': vod_remarks,
                            'label': label,
                            'url': url,
                            'klass': vod_class,
                            'type': type_name,
                        })

seen = set()
unique = []
for r in all_results:
    if r['url'] not in seen:
        seen.add(r['url'])
        unique.append(r)

groups = defaultdict(list)
for r in unique:
    groups[r['name']].append(r)

kw = keyword.lower()
def relevance(pair):
    name = pair[0].lower()
    if name == kw: return 0
    if kw in name: return 1
    return 2

sorted_groups = sorted(groups.items(), key=relevance)

for name, items in sorted_groups[:15]:
    best = items[0]
    best_url = items[0]['url']
    best_label = items[0]['label']
    for it in items:
        lbl = it['label'].lower()
        if '4k' in lbl or '1080' in lbl or 'hd' in lbl:
            best_url = it['url']
            best_label = it['label']
            break
    
    episodes = '|||'.join([f\"{it['label']}@@{it['url']}@@{it['type']}\" for it in items[:30]])
    type_name = best.get('type', '')
    
    print(f\"CMS_RESULT|{name}|{best['year']}|{best['remarks']}|{best_label}|{best_url}|{type_name}|{best['klass']}|{len(items)}|{episodes}\")
" > "$TMPDIR/cms_output" 2>/dev/null

# 验证 m3u8 可用性
CMS_VERIFIED="$TMPDIR/cms_verified"
touch "$CMS_VERIFIED"

if [ -s "$TMPDIR/cms_output" ]; then
    while IFS='|' read -r tag name year remarks label url type_name klass count rest; do
        [ "$tag" != "CMS_RESULT" ] && continue
        [ -z "$url" ] && continue
        (
            HTTP=$(curl -s --max-time 6 -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
            if [ "$HTTP" = "200" ]; then
                echo "CMS_OK|${name}|${year}|${remarks}|${label}|${url}|${type_name}|${klass}|${count}|${rest}" >> "$CMS_VERIFIED"
            fi
        ) &
    done < "$TMPDIR/cms_output"
    wait
fi

CMS_OK=$(grep -c '^CMS_OK' "$CMS_VERIFIED" 2>/dev/null || echo 0)
CMS_OK=$((CMS_OK + 0))

echo "SEARCH_SUMMARY|0|0|$CMS_OK|cms"
if [ -s "$CMS_VERIFIED" ]; then
    cat "$CMS_VERIFIED"
fi

rm -rf "$TMPDIR"
exit 0
