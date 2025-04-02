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

# 解析数据库 URL
parse_db_url() {
    local url="$1"
    local db_type="$2"
    
    case "$db_type" in
        "mysql")
            echo "$url" | sed -n "s/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\1:\2:\3:\4:\5/p"
            ;;
        "postgres")
            echo "$url" | sed -n "s/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\1:\2:\3:\4:\5/p"
            ;;
        *)
            log "ERROR" "不支持的数据库类型: ${db_type}"
            return 1
            ;;
    esac
}

# 验证备份文件
verify_backup() {
    local backup_file="$1"
    local db_type="$2"
    
    if [ ! -f "${backup_file}" ]; then
        log "ERROR" "备份文件不存在: ${backup_file}"
        return 1
    fi
    
    # 检查文件大小
    local file_size=$(stat -c%s "${backup_file}" 2>/dev/null || stat -f%z "${backup_file}")
    if [ "$file_size" -eq 0 ]; then
        log "ERROR" "备份文件为空: ${backup_file}"
        return 1
    fi
    
    # 检查文件完整性
    if ! gzip -t "${backup_file}" 2>/dev/null; then
        log "ERROR" "备份文件损坏: ${backup_file}"
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
    local db_type
    local db_name
    
    # 确定数据库类型
    if [[ $url == mysql://* ]]; then
        db_type="mysql"
    elif [[ $url == postgres://* ]]; then
        db_type="postgres"
    else
        log "ERROR" "不支持的数据库 URL 格式: ${url}"
        return 1
    fi
    
    # 解析数据库 URL
    local parsed_url
    parsed_url=$(parse_db_url "$url" "$db_type")
    if [ -z "$parsed_url" ]; then
        log "ERROR" "解析数据库 URL 失败: ${url}"
        return 1
    fi
    
    # 提取连接信息
    IFS=':' read -r user pass host port db_name <<< "$parsed_url"
    
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
    
    case "$db_type" in
        "mysql")
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
                --ssl=0 \
                "$db_name" \
                > "${backup_file}"; then
                log "ERROR" "数据库 ${db_name} 备份失败"
                rm -f "${backup_file}"
                return 1
            fi
            ;;
        "postgres")
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
            ;;
    esac

    # 压缩备份文件
    if ! gzip -${COMPRESSION_LEVEL} -f "${backup_file}"; then
        log "ERROR" "压缩备份文件失败: ${backup_file}"
        rm -f "${backup_file}"
        return 1
    fi
    
    # 验证备份文件
    if ! verify_backup "${backup_file}.gz" "$db_type"; then
        rm -f "${backup_file}.gz"
        return 1
    fi
    
    log "INFO" "数据库 ${db_name} 备份成功"
    
    # 清理过期备份
    cleanup_old_backups "$backup_dir" "$db_name"
    
    # 提交到 git 仓库
    if [ -d "${REPO_DIR}/.git" ]; then
        cd "${REPO_DIR}" || exit 1
        
        # 检查是否存在锁文件
        if [ -f ".git/index.lock" ]; then
            log "WARN" "发现 Git 锁文件，尝试删除..."
            rm -f .git/index.lock
        fi
        
        # 添加文件到暂存区
        if ! git add "${backup_dir}/backup_${date_str}.sql.gz"; then
            log "WARN" "数据库 ${db_name} 备份添加到 git 暂存区失败"
            return 0
        fi
        
        # 尝试提交，最多重试3次
        max_retries=3
        retry_count=1
        while [ $retry_count -le $max_retries ]; do
            if git commit -m "备份数据库 ${db_name} - ${date_str}"; then
                log "INFO" "数据库 ${db_name} 备份已提交到 git 仓库"
                break
            else
                if [ $retry_count -eq $max_retries ]; then
                    log "WARN" "数据库 ${db_name} 备份提交到 git 仓库失败（已重试${max_retries}次）"
                    break
                fi
                log "WARN" "数据库 ${db_name} 备份提交失败，${retry_count}秒后重试..."
                sleep $retry_count
                retry_count=$((retry_count + 1))
            fi
        done
    else
        log "WARN" "未找到 git 仓库，跳过提交操作"
    fi
    
    return 0
}

# 从文件读取数据库连接字符串
read_database_urls() {
    local urls_file="${REPO_DIR}/${DATABASE_CONFIG_FILE:-database_urls.txt}"
    
    if [ ! -f "${urls_file}" ]; then
        log "ERROR" "数据库连接字符串文件不存在: ${urls_file}"
        return 1
    fi
    
    # 读取非空行和非注释行，并过滤掉空白字符
    DATABASE_URLS=$(grep -v '^#' "${urls_file}" | grep -v '^[[:space:]]*$' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '\n' ',' | sed 's/,$//')
    
    if [ -z "${DATABASE_URLS}" ]; then
        log "ERROR" "未找到有效的数据库连接字符串，请在 ${DATABASE_CONFIG_FILE:-database_urls.txt} 中配置"
        return 1
    fi
    
    # 记录找到的数据库连接字符串数量
    local count=$(echo "${DATABASE_URLS}" | tr ',' '\n' | wc -l)
    log "INFO" "从文件中读取到 ${count} 个数据库连接字符串"
    
    export DATABASE_URLS
    return 0
}

# 并行备份函数
parallel_backup() {
    local urls=("$@")
    local max_parallel="${MAX_PARALLEL_BACKUPS:-3}"
    local pids=()
    
    for url in "${urls[@]}"; do
        # 等待，直到有足够的并行槽位
        while [ ${#pids[@]} -ge "$max_parallel" ]; do
            for i in "${!pids[@]}"; do
                if ! kill -0 "${pids[$i]}" 2>/dev/null; then
                    unset 'pids[$i]'
                    pids=("${pids[@]}")
                fi
            done
            sleep 1
        done
        
        # 启动新的备份进程
        backup_database "$url" &
        pids+=($!)
        log "INFO" "启动数据库备份进程: $url (PID: ${pids[-1]})"
    done
    
    # 等待所有进程完成
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
}

# Git 分支同步函数
sync_git_branch() {
    if [ ! -d "${REPO_DIR}/.git" ]; then
        log "WARN" "未找到 git 仓库，跳过分支同步"
        return 0
    fi
    
    cd "${REPO_DIR}" || exit 1
    
    # 检查是否存在锁文件
    if [ -f ".git/index.lock" ]; then
        log "WARN" "发现 Git 锁文件，尝试删除..."
        rm -f .git/index.lock
    fi
    
    # 获取当前分支
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    
    # 如果不在 main 分支，切换到 main 分支
    if [ "$current_branch" != "main" ]; then
        log "INFO" "切换到 main 分支"
        if ! git checkout main; then
            log "ERROR" "切换到 main 分支失败"
            return 1
        fi
    fi
    
    # 拉取最新代码
    log "INFO" "同步远程代码"
    if ! git pull origin main; then
        log "ERROR" "同步远程代码失败"
        return 1
    fi
    
    return 0
}

# Git 推送函数
push_to_remote() {
    if [ ! -d "${REPO_DIR}/.git" ]; then
        log "WARN" "未找到 git 仓库，跳过推送操作"
        return 0
    fi
    
    cd "${REPO_DIR}" || exit 1
    
    # 检查是否存在锁文件
    if [ -f ".git/index.lock" ]; then
        log "WARN" "发现 Git 锁文件，尝试删除..."
        rm -f .git/index.lock
    fi
    
    # 尝试推送，最多重试3次
    max_retries=3
    retry_count=1
    while [ $retry_count -le $max_retries ]; do
        if git push -f -u origin HEAD:main; then
            log "INFO" "所有备份已成功推送到远程仓库"
            break
        else
            if [ $retry_count -eq $max_retries ]; then
                log "WARN" "推送到远程仓库失败（已重试${max_retries}次）"
                break
            fi
            log "WARN" "推送到远程仓库失败，${retry_count}秒后重试..."
            sleep $retry_count
            retry_count=$((retry_count + 1))
        fi
    done
}

# 主函数
main() {
    # 验证环境变量
    validate_env_vars
    
    # 检查磁盘空间
    if ! check_disk_space; then
        exit 1
    fi
    
    # 同步 Git 分支
    if ! sync_git_branch; then
        exit 1
    fi
    
    # 读取数据库连接字符串
    if ! read_database_urls; then
        exit 1
    fi
    
    # 获取数据库 URL 列表
    urls=(${DATABASE_URLS//,/ })
    
    # 并行备份所有数据库
    parallel_backup "${urls[@]}"
    
    log "INFO" "所有数据库备份完成"
    
    # 统一推送到远程仓库
    push_to_remote
}

# 执行主函数
main
