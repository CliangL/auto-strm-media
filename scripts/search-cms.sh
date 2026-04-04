#!/bin/bash
# CMS API 搜索脚本 v1.1
# 从 LunaTV 苹果CMS V10 API 搜索影视，提取 m3u8 链接
# 用法: bash search-cms.sh "关键词" [最大源数]

KEYWORD="$1"
MAX_SOURCES="${2:-10}"
TMPDIR="/tmp/cms-search-$$"
mkdir -p "$TMPDIR"

if [ -z "$KEYWORD" ]; then
    echo "用法: bash search-cms.sh '关键词' [最大源数]"
    exit 1
fi

ENCODED_KW=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$KEYWORD")

# ============================================
# CMS 源列表（正规影视源，已过滤）
# ============================================
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
  "https://api.maoyanapi.top/api.php/provide/vod|猫眼资源"
  "https://iqiyizyapi.com/api.php/provide/vod|爱奇艺"
  "https://caiji.dbzy5.com/api.php/provide/vod|豆瓣资源"
  "https://caiji.maotaizy.cc/api.php/provide/vod|茅台资源"
  "https://ikunzyapi.com/api.php/provide/vod|iKun资源"
  "http://caiji.dyttzyapi.com/api.php/provide/vod|电影天堂"
  "https://subocaiji.com/api.php/provide/vod|速播资源"
  "https://jinyingzy.com/api.php/provide/vod|金鹰点播"
  "https://p2100.net/api.php/provide/vod|飘零资源"
  "https://api.ukuapi88.com/api.php/provide/vod|U酷影视"
  "https://api.wwzy.tv/api.php/provide/vod|旺旺资源"
  "https://api.xinlangapi.com/xinlangapi.php/provide/vod|新浪资源"
)

# ============================================
# 并行搜索所有 CMS 源
# ============================================
COUNT=0
for entry in "${SOURCE_LIST[@]}"; do
    [ "$COUNT" -ge "$MAX_SOURCES" ] && break
    API=$(echo "$entry" | cut -d'|' -f1)
    NAME=$(echo "$entry" | cut -d'|' -f2)
    SAFE=$(echo "$NAME" | tr -c 'a-zA-Z0-9' '_')
    
    (
        RESULT=$(curl -s --max-time 8 "${API}/?ac=detail&wd=${ENCODED_KW}" 2>/dev/null)
        TOTAL=$(echo "$RESULT" | jq -r '.total' 2>/dev/null)
        if [ "$TOTAL" -gt 0 ] 2>/dev/null; then
            echo "$RESULT" > "$TMPDIR/${SAFE}.json"
        fi
    ) &
    
    COUNT=$((COUNT + 1))
done
wait

# ============================================
# Python 汇总 + 去重
# ============================================
python3 << 'PYEOF'
import json, os, sys
from collections import defaultdict

tmpdir = os.environ.get('TMPDIR', '/tmp/cms-search')
keyword = os.environ.get('KEYWORD', '')

all_results = []

for fname in os.listdir(tmpdir):
    if not fname.endswith('.json'):
        continue
    source_name = fname.replace('.json', '').replace('_', ' ')
    fpath = os.path.join(tmpdir, fname)
    
    # 找到对应的源名
    source_label = source_name
    for entry in os.environ.get('SOURCE_LIST_STR', '').split(' '):
        pass  # 用文件名里的源名即可
    
    try:
        with open(fpath) as f:
            data = json.load(f)
    except:
        continue
    
    for item in data.get('list', []):
        vod_name = item.get('vod_name', '')
        vod_year = item.get('vod_year', '')
        vod_remarks = item.get('vod_remarks', '')
        vod_class = item.get('vod_class', '')
        vod_area = item.get('vod_area', '')
        
        play_from = item.get('vod_play_from', '')
        play_url = item.get('vod_play_url', '')
        
        froms = play_from.split('$$$')
        url_groups = play_url.split('$$$')
        
        for src, urls in zip(froms, url_groups):
            segments = urls.split('#')
            for seg in segments:
                parts = seg.split('$')
                if len(parts) == 2:
                    label, url = parts[0], parts[1]
                    if '.m3u8' in url and url.startswith('http'):
                        all_results.append({
                            'name': vod_name,
                            'year': vod_year,
                            'remarks': vod_remarks,
                            'label': label,
                            'url': url,
                            'source': source_label,
                            'klass': vod_class,
                            'area': vod_area,
                        })

# 去重相同 URL，保留第一个
seen_urls = set()
unique = []
for r in all_results:
    if r['url'] not in seen_urls:
        seen_urls.add(r['url'])
        unique.append(r)

total = len(unique)
print(f"CMS|{total}")

# 按影片分组
groups = defaultdict(list)
for r in unique:
    key = f"{r['name']}"
    groups[key].append(r)

# 按相关度排序（标题包含关键词的排前面）
def relevance(item):
    name = item[0].lower()
    kw = keyword.lower()
    if name == kw:
        return 0
    if kw in name:
        return 1
    return 2

sorted_groups = sorted(groups.items(), key=lambda x: relevance(x))

for name, items in sorted_groups[:20]:  # 最多显示20部
    # 每部片选代表链接（取不同源的各一个）
    best = items[0]
    year = best['year']
    remarks = best['remarks']
    klass = best['klass']
    
    # 选取一个最佳 m3u8（优先标签含 4K/1080）
    best_url = items[0]['url']
    best_label = items[0]['label']
    best_source = items[0]['source']
    for item in items:
        lbl = item['label'].lower()
        if '4k' in lbl or '1080' in lbl:
            best_url = item['url']
            best_label = item['label']
            best_source = item['source']
            break
    
    # 收集所有可用链接（用于创建 STRM）
    all_urls = '|'.join([f"{it['label']}@@{it['url']}@@{it['source']}" for it in items[:5]])
    
    print(f"CMS_ITEM|{name}|{year}|{remarks}|{best_label}|{best_url}|{best_source}|{klass}|{len(items)}|{all_urls}")

PYEOF

rm -rf "$TMPDIR"
exit 0
