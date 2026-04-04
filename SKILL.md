---
name: auto-strm-media
description: "Auto media system: search resources, generate STRM files, track TV series updates / 自动影视系统：搜索影视资源、生成STRM文件、追剧更新检查"
metadata:
  {
    "builtin_skill_version": "1.0",
    "copaw":
      {
        "emoji": "🎬",
        "requires": {}
      }
  }
---

# auto-strm-media - Auto Media System / 自动影视系统

**English**: Search → Validate → Select → User Save → Generate STRM (from TV directory) → Play

**中文**: 搜索 → 验证 → 选择 → 用户保存 → 从网盘TV生成STRM → 高清播放

---

## Use Cases / 使用场景

- "我想看 xxx" / "I want to watch xxx"
- "下载电影 xxx" / "Download movie xxx"
- "找 xxx 资源" / "Find xxx resources"

---

## Key Concept / 核心概念

**⚠️ 重要：高清播放必须用网盘TV目录！**

| Directory | Purpose | HD Playback |
|-----------|---------|-------------|
| `/🍊我的夸克分享/` | Manual import | ❌ No |
| `/每日更新/` | Index directory | ❌ No |
| `/🍆夸克网盘TV/来自分享/` | **Streaming playback** | ✅ **Yes** |

**Why?** 夸克/UC 网盘的高清资源只有在网盘TV目录下才能流媒体播放。

---

## Requirements / 系统要求

### Required Software / 必备软件

| Software | Version | Purpose |
|----------|---------|---------|
| Docker | 20+ | Container runtime |
| Docker Compose | 2+ | Container orchestration |
| jq | 1.6+ | JSON parsing |
| python3 | 3.8+ | URL encoding |

### Required Containers / 必备容器

| Container | Port | Purpose |
|-----------|------|---------|
| xiaoya/g-box | 5678 | Media server + streaming |
| g-box | 4567 | Cloud drive manager |
| pansou | 8080 | Resource search |

---

## Configuration / 配置清单

| Config Item | Description | How to Get |
|-------------|-------------|------------|
| `NAS_HOST` | NAS SSH hostname | `YOUR_USERNAME@YOUR_TAILSCALE_IP` |
| `NAS_LAN_HOST` | NAS LAN IP for STRM | `YOUR_LAN_IP` (局域网) |
| `NAS_USER` | NAS SSH username | Your NAS username |
| `NAS_PASS` | NAS SSH password | Your NAS password |
| `GBOX_USER` | g-box username | Default: `admin` |
| `GBOX_PASS` | g-box password | Set in g-box |
| `TMDB_API_KEY` | TMDB API key | https://www.themoviedb.org/settings/api |

**⚠️ 重要 IP 配置**：
- **xiaoya API 监控用**：`http://YOUR_TAILSCALE_IP:5678`（Tailscale，从外部可访问）
- **STRM URL 生成用**：`http://YOUR_LAN_IP:5678`（局域网，播放用）

---

## Complete Workflow / 完整流程

### Step 1: Search / 搜索

```
Search "keyword"
  ↓
① xiaoya local index (0.08s)
  ├─ Results → Validate → Show to user
  └─ No results ↓
② pansou API (Quark/115/Aliyun)
  ├─ Results → Validate availability → Show VALID links
  └─ No results ↓
③ moontv 资源站 (26 个资源站)
  ├─ Login → Get sources → Search each source
  ├─ Results → Parse m3u8 URLs → Show to user
  └─ No results → Not found
```

### Step 2: User Selection / 用户选择

**⚠️ pansou 资源需要用户手动保存！**

**For pansou resources:**
1. AI provides **valid share link**
2. **User manually**: Open Quark/UC app → Open share link → **Save to My Drive**
3. Wait for xiaoya to sync to `/🍆夸克网盘TV/来自分享/`
4. AI creates STRM from TV directory

### Step 3: User Save to My Drive / 用户保存到我的网盘

**⚠️ User action required - AI cannot do this!**

1. **AI provides**: Valid share link
2. **User actions**:
   - Open Quark/UC app or website
   - Open the share link
   - Click "Save to My Drive" / 「保存到我的网盘」
   - Choose save location
3. **Wait**: xiaoya auto-syncs to `/🍆夸克网盘TV/来自分享/`
4. **AI continues**: Create STRM from TV directory

### Step 4: Generate STRM (from TV directory) / 从网盘TV生成STRM

**⚠️ Critical: STRM path MUST use TV directory for HD playback!**

```
Source: /🍆夸克网盘TV/来自分享/资源名/
   ↓
STRM: /vol1/1000/docker/xiaoya/strm/C-每日更新/电视剧/资源名/Season 1/
```

**Example**:
```bash
# Video path in TV directory
VIDEO_PATH="/🍆夸克网盘TV/来自分享/白日提灯/S01E01.mp4"

# xiaoya URL (HD streaming)
URL="http://NAS_IP:5678/d/${VIDEO_PATH}"

# STRM file
echo "$URL" > "/vol1/1000/docker/xiaoya/strm/C-每日更新/电视剧/白日提灯/Season 1/S01E01.strm"
```

### Step 5: Monitor Updates / 监控更新

**Monitor TV directory**:
```
/🍆夸克网盘TV/来自分享/资源名/
```

When new episodes appear:
1. Detect new files in TV directory
2. Generate STRM for new episodes
3. Notify user

---

## Directory Structure / 目录结构

### xiaoya Structure / xiaoya 目录

```
/
├── 🍆夸克网盘TV/           ← HD streaming (use this!)
│   └── 来自分享/
│       └── [User saved resources]/
├── 🍊我的夸克分享/          ← Manual import (no HD)
├── 每日更新/                ← Index (no HD)
└── ...
```

### STRM Structure / STRM 目录

```
/vol1/1000/docker/xiaoya/strm/C-每日更新/
├── 电影/
├── 电视剧/
│   └── 资源名/
│       └── Season 1/
│           ├── S01E01.strm
│           └── S01E02.strm
├── 动漫/
├── 纪录片/
├── 综艺/
└── 网络资源/          ← CMS m3u8 resources
```

---

## Monitoring / 监控机制

**Monitor Directory**: `/🍆夸克网盘TV/来自分享/`

| Directory | Monitored |
|-----------|-----------|
| `/🍆夸克网盘TV/来自分享/` | ✅ Auto monitored |
| `/🍊我的夸克分享/` | ❌ Not monitored |
| `/每日更新/` | ❌ Not monitored |

---

## Scripts Reference / 脚本说明

| Script | Function |
|--------|----------|
| `search-media.sh "keyword"` | Search media (main entry) |
| `search-cms.sh "keyword"` | CMS API search (backup) |
| `media-info.sh "title"` | Get TMDB info (3s) |
| `check-drama.sh` | Check TV series updates |
| `update-index.sh` | Update local index cache |

---

## Notes / 注意事项

- **HD playback requires TV directory** - `/🍆夸克网盘TV/来自分享/`
- **User must manually save to My Drive** - AI cannot do this
- All curl commands use `--max-time` to prevent hanging
- Chinese paths in STRM URLs must be URL encoded

---

### 8. moontv 资源站接入 (v4.4 新增)

**moontv** 是 LunaTV 增强版影视聚合平台，包含 26 个影视资源站的 CMS API。

**接口**：`/api/source-test?q=关键词&source=资源站key`

**特点**：
- 返回 m3u8 直链，可直接创建 STRM
- 每个资源站独立 API，需遍历搜索
- 部分站点可能有广告或不稳定

**STRM 存储位置**：网络资源目录（不是 xiaoya 网盘）

```
STRM 目录：/vol1/1000/docker/xiaoya/strm/C-每日更新/网络资源/
```

**格式**：m3u8 直链 → STRM 文件

---

## ⚠️ Critical Rules / 关键规则（必须遵守）

### 1. xiaoya 搜索验证

**❌ 错误做法**：直接访问目录路径验证
```bash
curl "http://NAS:5678/d/每日更新/电视剧/国产剧/资源名"  # 返回 500 错误！
```

**✅ 正确做法**：用 API 检查目录内容
```bash
curl -s "http://NAS:5678/api/fs/list?path=/每日更新/电视剧/国产剧/资源名" | jq '.data.content | length'
```

**原因**：目录路径不能直接访问，但目录内的文件可以播放。必须用 API 检查目录是否有视频文件。

### 2. pansou 资源验证

**❌ 错误做法**：只验证链接能否打开（返回 200 不代表资源有效！）
```bash
# ❌ 错误！返回 200 只代表页面可访问，不代表有视频文件
curl -s "https://pan.quark.cn/s/xxx" -o /dev/null -w "%{http_code}"
```

**✅ 正确做法**：
1. **pansou API 搜索结果** → 直接展示给用户，让用户自己判断
2. **不要替用户验证** pansou 链接是否有效，因为：
   - 链接可能在分享时就已失效
   - xiaoya 可能未同步到该资源
   - 目录里可能是压缩包而非视频

```
pansou 搜索结果 → 直接展示链接 → 用户自己打开确认
```

**✅ 正确流程**：
```
1. AI 展示搜索结果（pansou API 返回的链接）
2. 用户打开链接自行验证
3. 用户确认要保存 → 保存到夸克网盘
4. xiaoya 同步到网盘TV目录
5. AI 用 xiaoya API 验证同步后的资源
```

**⚠️ 重要**：不要在展示给用户之前用 curl 验证 pansou 链接，这种验证无效！

### 3. 验证 xiaoya 同步后的资源

用户说"已保存"后，必须用 xiaoya API 验证：

```bash
# ✅ 正确：用 xiaoya API 检查网盘TV目录
curl -s "http://NAS:5678/api/fs/list?path=/🍆夸克网盘TV/来自分享/资源名" | jq '.data.content | length'

# ✅ 正确：检查是否有视频文件
curl -s "http://NAS:5678/api/fs/list?path=/🍆夸克网盘TV/来自分享/资源名" | jq '.data.content[].name' | grep -ciE 'mkv|mp4|ts'
```

### 4. 资源优先级

```
优先级排序：
1. xiaoya 本地已有资源 → 直接可用
2. UC/115 网盘 → 高清流媒体
3. 夸克网盘 → 需保存到网盘TV目录
4. pansou 搜索结果 → 展示给用户，用户自行验证
```

### 5. 区分不同版本

**⚠️ 删除前必须确认！**

同一剧集可能有多个版本：
- 电视剧版 vs 动漫版
- 第一季 vs 第二季 vs 特别篇
- 不同清晰度版本（4K/1080P/720P）

**流程**：
1. 告诉用户有哪些版本
2. 确认用户要看哪个版本
3. 只删除用户不需要的版本
4. 生成用户要的版本 STRM

**示例**：
```
凡人修仙传：
- 电视剧版（30集，真人）
- 动漫版（172集，星海飞驰篇）
- 剧场版（虚天战纪）

❌ 错误：直接删除电视剧版
✅ 正确：先问用户要看哪个版本
```

### 6. STRM 文件创建

**⚠️ 路径必须 URL encode！**

```bash
# ❌ 错误：中文路径不编码
URL="http://NAS:5678/d/每日更新/电视剧/国产剧/资源名/第01集.mp4"

# ✅ 正确：URL encode 中文
URL="http://NAS:5678/d/%E6%AF%8F%E6%97%A5%E6%9B%B4%E6%96%B0/%E7%94%B5%E8%A7%86%E5%89%A7/..."

# 用 python3 编码
ENCODED=$(python3 -c "import urllib.parse; print(urllib.parse.quote('每日更新/电视剧/国产剧/资源名/第01集.mp4'))")
```

### 7. 追剧路径追踪（⭐ 关键规则）

**每次追剧时，必须记录资源的来源文件夹路径！**

来源文件夹 = xiaoya 中该资源所在的目录（用户保存/转存后 xiaoya 自动同步到的那个目录）

**如何找到来源文件夹**：
1. 用户从 pansou 保存链接到夸克网盘
2. xiaoya 自动同步到 `/🍊我的夸克分享/` 下的某个目录
3. 这个目录就是**来源文件夹**，只监控这一个

**示例**：
```
用户保存「白日提灯」到夸克 → xiaoya 同步到：
/🍊我的夸克分享/C电视剧/白日提灯/B白日KAI灯/

追剧时只监控这个目录，有新文件就生成 STRM
```

**❌ 错误**：监控整个 xiaoya 或整个每日更新目录
**✅ 正确**：只监控该资源转存来源的那一个文件夹

### 8. 完整流程检查清单

每次处理影视请求时，必须检查：

```
□ 搜索
  □ xiaoya 本地索引（用 API 验证）
  □ pansou API（筛选 UC/115，验证格式和集数）
  
□ 验证
  □ 用 /api/fs/list 检查目录
  □ 统计视频文件数量（mp4/mkv/ts）
  □ 确认不是压缩包
  
□ 用户选择
  □ 列出所有版本
  □ 确认用户要看哪个版本
  □ 记录来源文件夹路径（添加到 drama-state.json）
  
□ 入库
  □ URL encode 中文路径
  □ 创建正确目录结构
  □ 验证 STRM 文件可播放
  □ 同时更新 drama-state.json 的 xiaoya_path
  
□ 追剧
  □ 确认剧集状态（完结/更新中）
  □ 更新中的添加到追剧列表（带 xiaoya_path）
  □ 以后只监控 xiaoya_path 这一个目录
```

---

## Changelog / 更新日志

### v4.6 (2026-04-04)
- **Security**: 脱敏处理，所有真实 IP、用户名、密码已替换为占位符
- **Compliance**: 符合 GitHub 发布规范，零敏感信息泄露
- **Improved**: 添加配置说明，用户可轻松替换占位符

### v4.5 (2026-04-04)
- Fixed: 搜索功能完全重写，绕过失效的 xiaoya API 验证
- Fixed: 修复并行验证导致输出丢失的问题
- Changed: 直接使用本地索引（31.5万条记录）+ pansou API 作为主要搜索源
- Added: 跳过 API 验证，直接展示结果让用户自行判断

### v4.4 (2026-04-03)
- Added: moontv 资源站搜索作为第三步
- Feature: 直接返回 m3u8 直链，可创建 STRM
- Added: 追剧监控 xiaoya 来源目录（只监控转存文件夹）
- Fixed: check-drama.sh 重写，监控 xiaoya API 而非本地 STRM
- Fixed: STRM URL 使用正确的局域网 IP `YOUR_LAN_IP:5678`
- Added: xiaoya API 监控使用 Tailscale IP `YOUR_TAILSCALE_IP:5678`
- Fixed: 批量替换 194 个 STRM 文件 IP 地址

### v4.3 (2026-04-03)
- Changed: STRM generated from TV directory for HD playback
- Added: User save workflow for pansou resources
- Fixed: Monitoring correct TV directory

### v4.2 (2026-04-03)
- Fixed: pansou search with Tailscale IP
- Fixed: g-box API correct endpoints
- Added: Monitoring directory documentation