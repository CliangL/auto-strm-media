#!/bin/bash
# 更新本地媒体索引缓存
# 用法: bash update-index.sh

INDEX_DIR="/Users/cliang/.openclaw/workspace/data"
NAS_HOST="${NAS_HOST:-YOUR_USERNAME@YOUR_TAILSCALE_IP}"
NAS_PASS="${NAS_PASS:-YOUR_PASSWORD}"
INDEX_FILE="media-index.txt"

mkdir -p "$INDEX_DIR"

echo "$(date '+%Y-%m-%d %H:%M'): 开始更新索引..."

# 从 NAS 下载索引文件（压缩传输）
sshpass -p "$NAS_PASS" ssh -o StrictHostKeyChecking=no "$NAS_HOST" \
  'gzip -c /vol1/1000/docker/xiaoya/index/index.video.txt' | gunzip > "$INDEX_DIR/$INDEX_FILE"

if [ $? -eq 0 ]; then
  LINES=$(wc -l < "$INDEX_DIR/$INDEX_FILE")
  SIZE=$(ls -lh "$INDEX_DIR/$INDEX_FILE" | awk '{print $5}')
  echo "$(date '+%Y-%m-%d %H:%M'): ✅ 索引更新完成，$LINES 条记录，$SIZE"
else
  echo "$(date '+%Y-%m-%d %H:%M'): ❌ 索引更新失败"
  exit 1
fi
