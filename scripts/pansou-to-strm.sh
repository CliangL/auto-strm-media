#!/bin/bash
# pansou 分享链接转 STRM 脚本
# 用法: bash pansou-to-strm.sh "分享URL" "保存路径" "网盘类型"
# 网盘类型: quark, aliyun, uc, 115

SHARE_URL="$1"
SAVE_PATH="$2"
DRIVE_TYPE="$3"
NAS_HOST="${NAS_HOST:-YOUR_TAILSCALE_IP}"
NAS_USER="${NAS_USER:-YOUR_USERNAME}"
NAS_PASS="${NAS_PASS:-YOUR_PASSWORD}"

if [ -z "$SHARE_URL" ] || [ -z "$DRIVE_TYPE" ]; then
    echo "用法: bash pansou-to-strm.sh '分享URL' '保存路径' '网盘类型(quark/aliyun/uc/115)'"
    exit 1
fi

# 提取 share_id
SHARE_ID=$(echo "$SHARE_URL" | grep -oE '[a-f0-9]{10,20}' | head -1)

if [ -z "$SHARE_ID" ]; then
    echo "ERROR|无法从 URL 提取 share_id"
    exit 1
fi

echo "SHARE_ID|$SHARE_ID"

# ============================================
# 根据网盘类型获取 file_id
# ============================================
case "$DRIVE_TYPE" in
    quark)
        # 夸克 API 需要登录 cookie
        COOKIE=$(sshpass -p "$NAS_PASS" ssh "$NAS_USER@$NAS_HOST" "docker exec g-box cat /data/quark_cookie.txt 2>/dev/null || cat /vol1/docker/xiaoya/mytoken.txt 2>/dev/null" | head -1)
        
        if [ -z "$COOKIE" ]; then
            echo "ERROR|夸克 cookie 未配置，请先在 g-box Web UI 登录夸克网盘"
            exit 1
        fi
        
        # 调用夸克 API 获取分享目录信息
        API_RESP=$(curl -s "https://drive-pc.quark.cn/1/clouddrive/share/sharepage/detail?pr=ucpro&fr=pc&share_id=$SHARE_ID&page=1&size=50" \
            -H "Cookie: $COOKIE" \
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
            --max-time 10 2>/dev/null)
        
        FILE_ID=$(echo "$API_RESP" | jq -r '.data.file_info_list[0].fid // .data.children[0].fid // empty' 2>/dev/null)
        
        if [ -z "$FILE_ID" ]; then
            echo "ERROR|夸克 API 获取 file_id 失败，可能需要登录或分享链接无效"
            exit 1
        fi
        
        SHARE_LIST="/data/quarkshare_list.txt"
        ;;
        
    aliyun)
        # 阿里云盘需要 refresh_token
        TOKEN=$(sshpass -p "$NAS_PASS" ssh "$NAS_USER@$NAS_HOST" "docker exec g-box cat /data/mytoken.txt 2>/dev/null || cat /vol1/docker/xiaoya/mytoken.txt 2>/dev/null" | head -1)
        
        if [ -z "$TOKEN" ]; then
            echo "ERROR|阿里云盘 token 未配置"
            exit 1
        fi
        
        # 阿里云盘 API
        API_RESP=$(curl -s "https://api.aliyundrive.com/v2/share_link/get_share_link_info" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"share_id":"$SHARE_ID"}' \
            --max-time 10 2>/dev/null)
        
        FILE_ID=$(echo "$API_RESP" | jq -r '.file_infos[0].file_id // empty' 2>/dev/null)
        
        if [ -z "$FILE_ID" ]; then
            echo "ERROR|阿里云盘 API 获取 file_id 失败"
            exit 1
        fi
        
        SHARE_LIST="/data/alishare_list.txt"
        ;;
        
    115)
        # 115 网盘
        COOKIE=$(sshpass -p "$NAS_PASS" ssh "$NAS_USER@$NAS_HOST" "docker exec g-box cat /data/115_cookie.txt 2>/dev/null || cat /vol1/docker/xiaoya/115_cookie.txt 2>/dev/null" | head -1)
        
        if [ -z "$COOKIE" ]; then
            echo "ERROR|115 cookie 未配置"
            exit 1
        fi
        
        # 115 API
        API_RESP=$(curl -s "https://webapi.115.com/share/getinfo?share_code=$SHARE_ID" \
            -H "Cookie: $COOKIE" \
            --max-time 10 2>/dev/null)
        
        FILE_ID=$(echo "$API_RESP" | jq -r '.data.file_id // empty' 2>/dev/null)
        
        if [ -z "$FILE_ID" ]; then
            echo "ERROR|115 API 获取 file_id 失败"
            exit 1
        fi
        
        SHARE_LIST="/data/115share_list.txt"
        ;;
        
    uc)
        # UC 网盘（与夸克同系）
        COOKIE=$(sshpass -p "$NAS_PASS" ssh "$NAS_USER@$NAS_HOST" "docker exec g-box cat /data/uc_cookie.txt 2>/dev/null" | head -1)
        
        if [ -z "$COOKIE" ]; then
            echo "ERROR|UC cookie 未配置"
            exit 1
        fi
        
        API_RESP=$(curl -s "https://drive-pc.quark.cn/1/clouddrive/share/sharepage/detail?pr=ucpro&fr=pc&share_id=$SHARE_ID&page=1&size=50" \
            -H "Cookie: $COOKIE" \
            -H "User-Agent: Mozilla/5.0" \
            --max-time 10 2>/dev/null)
        
        FILE_ID=$(echo "$API_RESP" | jq -r '.data.file_info_list[0].fid // empty' 2>/dev/null)
        
        if [ -z "$FILE_ID" ]; then
            echo "ERROR|UC API 获取 file_id 失败"
            exit 1
        fi
        
        SHARE_LIST="/data/ucshare_list.txt"
        ;;
        
    *)
        echo "ERROR|不支持的网盘类型: $DRIVE_TYPE"
        exit 1
        ;;
esac

echo "FILE_ID|$FILE_ID"

# ============================================
# 写入 share_list.txt
# ============================================
# 格式: 路径 share_id file_id
ENTRY="$SAVE_PATH  $SHARE_ID  $FILE_ID"

sshpass -p "$NAS_PASS" ssh "$NAS_USER@$NAS_HOST" "echo '$ENTRY' >> $SHARE_LIST"

echo "WRITTEN|$SHARE_LIST|$ENTRY"

# ============================================
# 触发 xiaoya 重新生成 STRM
# ============================================
sshpass -p "$NAS_PASS" ssh "$NAS_USER@$NAS_HOST" "docker exec g-box /index.sh 2>/dev/null || docker exec g-box touch /data/.strm_update 2>/dev/null"

echo "STRM_UPDATE|已触发 STRM 生成，请稍等几分钟"

# 返回 STRM 路径
STRM_PATH="/vol1/docker/xiaoya/strm/$SAVE_PATH"
echo "STRM_PATH|$STRM_PATH"

exit 0
