# 使用 alpine 镜像
FROM alpine:3.16

# 元数据标签
LABEL maintainer="lff <dev_lff@outlook.com>" \
      description="Database GitBackup - Automated database backup solution with Git integration" \
      version="1.0.0" \
      name="dbbackup" \
      org.opencontainers.image.source="https://github.com/l-ff/dbbackup" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.title="Database GitBackup"

# 环境变量
ENV BACKUP_DIR=/backup \
    BACKUP_LOG=/var/log/cron.log \
    CRON_SCHEDULE="0 2 * * *" \
    REPO_DIR=/backup/repo \
    MAX_BACKUPS=10 \
    APP_NAME="Database GitBackup" \
    APP_VERSION="1.0.0" \
    TZ=Asia/Shanghai \
    GIT_USER="AutoSync Bot" \
    GIT_EMAIL="autosync@bot.com" \
    COMPRESSION_LEVEL=6 \
    REQUIRED_SPACE=1000 \
    BACKUP_ON_START=false \
    DATABASE_CONFIG_FILE=database_urls.txt

# 添加 PostgreSQL 官方源并安装依赖
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" >> /etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    apk update && \
    apk add --no-cache \
    mariadb-client \
    mariadb-connector-c \
    postgresql17-client \
    gzip \
    git \
    curl \
    openssh-client \
    ca-certificates \
    dcron \
    procps \
    grep \
    tzdata \
    dos2unix \
    bash

# 配置时区
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# 创建目录结构
RUN mkdir -p ${BACKUP_DIR} ${REPO_DIR} /var/log ~/.ssh && \
    touch ${BACKUP_LOG} && \
    chown -R root:root ${BACKUP_DIR} && \
    chmod -R 755 ${BACKUP_DIR} && \
    chmod 700 ~/.ssh

# 配置定时任务
RUN echo "${CRON_SCHEDULE} bash ${BACKUP_DIR}/backup.sh >> ${BACKUP_LOG} 2>&1" > /etc/cron.d/db-backup && \
    chmod 0644 /etc/cron.d/db-backup && \
    echo "" >> /etc/cron.d/db-backup

# 复制脚本
COPY backup.sh ${BACKUP_DIR}/backup.sh
COPY entrypoint.sh /entrypoint.sh

# 设置脚本权限和转换换行符
RUN dos2unix /entrypoint.sh ${BACKUP_DIR}/backup.sh && \
    chmod +x /entrypoint.sh ${BACKUP_DIR}/backup.sh

# 设置工作目录
WORKDIR ${BACKUP_DIR}

# 健康检查
HEALTHCHECK --interval=5m --timeout=3s --start-period=30s --retries=3 \
    CMD bash -c '\
        if ! pgrep crond > /dev/null; then \
            echo "cron service is not running"; \
            exit 1; \
        fi; \
        if ! mysql --host="$MYSQL_HOST" --port="$MYSQL_PORT" \
            --user="$MYSQL_USER" --password="$MYSQL_PASSWORD" \
            -e "SELECT 1" > /dev/null; then \
            echo "cannot connect to MySQL"; \
            exit 1; \
        fi; \
        if [ ! -f "${BACKUP_LOG}" ]; then \
            echo "backup log file does not exist"; \
            exit 1; \
        fi'

ENTRYPOINT ["/entrypoint.sh"]
