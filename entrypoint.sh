#!/bin/bash
set -euo pipefail

# 常量定义
readonly LOG_PREFIX="[dbbackup]"
readonly REQUIRED_VARS="DATABASE_URLS GIT_REPO GIT_TOKEN"

# 日志函数
log() {
    local level="${1:-INFO}"
    shift
    local message="$*"
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "${LOG_PREFIX}[${timestamp}][${level}] ${message}"
}

# 错误处理
handle_error() {
    local exit_code=$1
    local line_no=$2
    log "ERROR" "脚本在第 ${line_no} 行发生错误，退出码: ${exit_code}"
    exit "${exit_code}"
}

# 验证环境变量
check_required_vars() {
    for var in ${REQUIRED_VARS}; do
        eval value=\$$var
        if [ -z "${value:-}" ]; then
            log "ERROR" "环境变量 ${var} 未设置"
            return 1
        fi
    done
    return 0
}

# 验证数据库连接
check_database_connection() {
    local urls=(${DATABASE_URLS//,/ })
    for url in "${urls[@]}"; do
        if [[ $url == mysql://* ]]; then
            # 解析 MySQL URL
            local host=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\3/p')
            local port=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\4/p')
            local user=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\1/p')
            local pass=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\2/p')
            local db=$(echo "$url" | sed -n 's/mysql:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\5/p')
            
            log "INFO" "验证 MySQL 连接: ${host}:${port}"
            if ! mysql --host="${host}" --port="${port}" \
                --user="${user}" --password="${pass}" \
                -e "SELECT 1" > /dev/null 2>&1; then
                log "ERROR" "无法连接到 MySQL 服务器: ${host}:${port}"
                return 1
            fi
        elif [[ $url == postgres://* ]]; then
            # 解析 PostgreSQL URL
            local host=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\3/p')
            local port=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\4/p')
            local user=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\1/p')
            local pass=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\2/p')
            local db=$(echo "$url" | sed -n 's/postgres:\/\/\([^:]*\):\([^@]*\)@\([^:]*\):\([0-9]*\)\/\(.*\)/\5/p')
            
            log "INFO" "验证 PostgreSQL 连接: ${host}:${port}"
            if ! PGPASSWORD="${pass}" psql -h "${host}" -p "${port}" -U "${user}" -d "${db}" -c "SELECT 1" > /dev/null 2>&1; then
                log "ERROR" "无法连接到 PostgreSQL 服务器: ${host}:${port}"
                return 1
            fi
        else
            log "ERROR" "不支持的数据库 URL 格式: ${url}"
            return 1
        fi
    done
    log "INFO" "所有数据库连接验证成功"
    return 0
}

# 配置 Git 仓库
setup_git_repo() {
    local repo_url="https://${GIT_TOKEN}@github.com/${GIT_REPO}.git"
    log "INFO" "Git 仓库地址: ${repo_url}"

    # 清理已存在的仓库
    if [ -d "${REPO_DIR}" ]; then
        log "INFO" "清理已存在的仓库目录..."
        rm -rf "${REPO_DIR}"
    fi

    # 克隆仓库
    if ! git clone "${repo_url}" "${REPO_DIR}"; then
        log "ERROR" "Git 仓库克隆失败"
        return 1
    fi
    log "INFO" "Git 仓库克隆成功"

    # 配置 Git
    cd "${REPO_DIR}"
    log "INFO" "配置 Git 凭据..."
    git config user.name "${GIT_USER:-AutoSync Bot}"
    git config user.email "${GIT_EMAIL:-autosync@bot.com}"
    git config core.fileMode false
    git config core.autocrlf input

    # 切换到主分支
    if ! git checkout main; then
        log "ERROR" "无法切换到 main 分支"
        return 1
    fi

    return 0
}

# 记录启动时间
record_start_time() {
    log "INFO" "记录启动时间..."
    echo "$(date +'%Y-%m-%d %H:%M:%S')" >> start_time.txt
    if ! git add start_time.txt || \
       ! git commit -m "记录启动时间" || \
       ! git push origin HEAD; then
        log "WARN" "GitHub 推送失败，但继续执行..."
    fi
}

# 主函数
main() {
    # 设置错误处理
    trap 'handle_error $? $LINENO' ERR

    # 显示启动信息
    log "INFO" "==================================================="
    log "INFO" "Database GitBackup Service (dbbackup) v${APP_VERSION}"
    log "INFO" "==================================================="

    # 验证环境
    check_required_vars || exit 1
    check_database_connection || exit 1

    # 设置 Git 仓库
    setup_git_repo || exit 1
    record_start_time

    # 启动 cron 服务
    log "INFO" "启动 cron 服务..."
    crond

    # 执行初始备份（如果启用）
    if [ "${BACKUP_ON_START:-false}" = "true" ]; then
        log "INFO" "执行初始备份..."
        if ! ${BACKUP_DIR}/backup.sh; then
            log "ERROR" "初始备份失败"
            exit 1
        fi
    fi

    # 保持容器运行
    log "INFO" "服务已启动，等待定时任务执行..."
    tail -f ${BACKUP_LOG}
}

# 执行主函数
main