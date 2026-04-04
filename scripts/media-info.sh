#!/bin/bash
# 快速查询影视信息（TMDB API）- 并行版
# 用法: bash media-info.sh "剧名"
# 输出: 类型|总集数|状态|评分|年份|季数

KEYWORD="$1"
TMDB_KEY="07f4dea0663fb3cb83cd968d4218a61d"

if [ -z "$KEYWORD" ]; then
    echo "用法: bash media-info.sh '剧名'"
    exit 1
fi

ENCODED=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$KEYWORD")

# 并行搜索电视剧和电影
curl -s --max-time 10 "https://api.themoviedb.org/3/search/tv?api_key=${TMDB_KEY}&query=${ENCODED}&language=zh-CN" > /tmp/tmdb_tv.json 2>/dev/null &
curl -s --max-time 10 "https://api.themoviedb.org/3/search/movie?api_key=${TMDB_KEY}&query=${ENCODED}&language=zh-CN" > /tmp/tmdb_movie.json 2>/dev/null &
wait

# 解析结果
python3 << 'PYEOF'
import json

results = []

# 电视剧
try:
    with open("/tmp/tmdb_tv.json") as f:
        tv_search = json.load(f)
    if tv_search.get("results"):
        tv_id = tv_search["results"][0]["id"]
        # 需要再请求详情...但我们可以从搜索结果拿到基本信息
        r = tv_search["results"][0]
        results.append(f"TV|{r['name']}|{r.get('vote_average',0)}|{r.get('first_air_date','')[:4]}|TMDB_ID:{tv_id}")
except:
    pass

# 电影
try:
    with open("/tmp/tmdb_movie.json") as f:
        movie_search = json.load(f)
    if movie_search.get("results"):
        r = movie_search["results"][0]
        results.append(f"MOVIE|{r['title']}|{r.get('vote_average',0)}|{r.get('release_date','')[:4]}")
except:
    pass

for r in results:
    print(r)
PYEOF

# 如果找到电视剧，获取详情（总集数、状态）
TV_ID=$(python3 -c "
import json
try:
    with open('/tmp/tmdb_tv.json') as f:
        d=json.load(f)
    if d.get('results'): print(d['results'][0]['id'])
except: pass
" 2>/dev/null)

if [ -n "$TV_ID" ]; then
    curl -s --max-time 10 "https://api.themoviedb.org/3/tv/${TV_ID}?api_key=${TMDB_KEY}&language=zh-CN" | \
        python3 -c "
import json,sys
d=json.load(sys.stdin)
eps=d.get('number_of_episodes',0)
seasons=d.get('number_of_seasons',0)
status=d.get('status','')
name=d.get('name','')
rating=d.get('vote_average',0)
year=(d.get('first_air_date','') or '')[:4]
print(f'DETAIL|{name}|{eps}|{seasons}|{status}|{rating}|{year}')
" 2>/dev/null
fi
