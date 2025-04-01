#!/bin/bash
set -euo pipefail

# 配置日志函数
log() {
    level="${1:-INFO}"
    shift
    message="$*"
    echo "[dbbackup][$(date +'%Y-%m-%d %H:%M:%S')][${level}] ${message}" | tee -a "${BACKUP_LOG}"
}

# 错误处理函数
handle_error() {
    exit_code=$1
    line_no=$2
    log "ERROR" "脚本在第 ${line_no} 行发生错误，退出码: ${exit_code}"
    exit "${exit_code}"
}

# 设置错误处理
trap 'handle_error $? $LINENO' ERR

# 验证环境变量
validate_env_vars() {
    required_vars="REPO_DIR BACKUP_LOG REQUIRED_SPACE MAX_BACKUPS COMPRESSION_LEVEL"
    
    for var in $required_vars; do
        if [ -z "${!var:-}" ]; then
            log "ERROR" "缺少必要的环境变量: ${var}"
            exit 1
        fi
    done
}

# 验证数据库名称
validate_db_name() {
    local db_name="$1"
    if ! echo "$db_name" | grep -qE '^[a-zA-Z0-9_]+$'; then
        log "ERROR" "数据库名称 ${db_name} 包含非法字符"
        return 1
    fi
    return 0
}

# 检查磁盘空间
check_disk_space() {
    available_space=$(df -m "${REPO_DIR}" | awk 'NR==2 {print $4}')
    
    if [ "${available_space}" -lt "${REQUIRED_SPACE}" ]; then
        log "ERROR" "磁盘空间不足，需要至少 ${REQUIRED_SPACE}MB，当前可用 ${available_space}MB"
        return 1
    fi
    return 0
}

# 清理过期备份
cleanup_old_backups() {
    backup_dir=$1
    db_name=$2
    
    # 获取所有备份文件并按时间排序
    backup_files=$(ls -t "${backup_dir}/backup_*.sql.gz" 2>/dev/null || true)
    
    # 计算需要删除的文件数量
    total_files=$(echo "$backup_files" | wc -l)
    if [ "$total_files" -gt "$MAX_BACKUPS" ]; then
        # 保留最新的MAX_BACKUPS个文件，删除其余文件
        echo "$backup_files" | tail -n +$((MAX_BACKUPS + 1)) | while read -r file; do
            if [ -f "$file" ]; then
                if ! rm -f "$file"; then
                    log "ERROR" "删除旧备份文件失败: $(basename "${file}")"
                    return 1
                fi
                log "INFO" "删除旧备份: $(basename "${file}")"
            fi
        done
    fi
}

# 备份单个数据库函数
backup_database() {
    local url="$1"
    local db_name
    
    if [[ $url == mysql://* ]]; then
        # 解析 MySQL URL
        local host=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\3/p')
        local port=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\4/p')
        local user=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\1/p')
        local pass=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\2/p')
        db_name=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\5/p')
    elif [[ $url == postgres://* ]]; then
        # 解析 PostgreSQL URL
        local host=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\3/p')
        local port=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\4/p')
        local user=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\1/p')
        local pass=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\2/p')
        db_name=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\5/p')
    else
        log "ERROR" "不支持的数据库 URL 格式: ${url}"
        return 1
    fi
    
    # 验证数据库名称
    if ! validate_db_name "$db_name"; then
        return 1
    fi
    
    backup_dir="${REPO_DIR}/${db_name}"
    date_str=$(date +%Y%m%d_%H%M%S)
    backup_file="${backup_dir}/backup_${date_str}.sql"
    
    # 创建数据库备份目录
    if ! mkdir -p "$backup_dir"; then
        log "ERROR" "创建备份目录失败: ${backup_dir}"
        return 1
    fi
    
    # 备份数据库
    log "INFO" "开始备份数据库: ${db_name}"
    
    if [[ $url == mysql://* ]]; then
        # MySQL 备份
        if ! mysqldump \
            --host="$host" \
            --port="$port" \
            --user="$user" \
            --password="$pass" \
            --events \
            --routines \
            --triggers \
            --single-transaction \
            --quick \
            --lock-tables=false \
            "$db_name" 2>/dev/null \
            > "${backup_file}"; then
            log "ERROR" "数据库 ${db_name} 备份失败"
            rm -f "${backup_file}"
            return 1
        fi
    elif [[ $url == postgres://* ]]; then
        # PostgreSQL 备份
        if ! PGPASSWORD="$pass" pg_dump \
            -h "$host" \
            -p "$port" \
            -U "$user" \
            -d "$db_name" \
            > "${backup_file}"; then
            log "ERROR" "数据库 ${db_name} 备份失败"
            rm -f "${backup_file}"
            return 1
        fi
    fi

    # 压缩备份文件
    if ! gzip -${COMPRESSION_LEVEL} -f "${backup_file}"; then
        log "ERROR" "压缩备份文件失败: ${backup_file}"
        rm -f "${backup_file}"
        return 1
    fi
    
    log "INFO" "数据库 ${db_name} 备份成功"
    
    # 清理过期备份
    cleanup_old_backups "$backup_dir" "$db_name"
    
    return 0
}

# 主函数
main() {
    # 验证环境变量
    validate_env_vars
    
    # 检查磁盘空间
    if ! check_disk_space; then
        exit 1
    fi
    
    # 获取数据库 URL 列表
    urls=(${DATABASE_URLS//,/ })
    
    # 备份每个数据库
    for url in "${urls[@]}"; do
        if ! backup_database "$url"; then
            log "ERROR" "备份数据库失败: ${url}"
            continue
        fi
    done
    
    log "INFO" "所有数据库备份完成"
}

# 执行主函数
main
