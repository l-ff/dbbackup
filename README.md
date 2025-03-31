# Database GitBackup

[![Docker Pulls](https://img.shields.io/docker/pulls/lff0/dbbackup)](https://hub.docker.com/r/lff0/dbbackup)
[![License](https://img.shields.io/github/license/l-ff/dbbackup)](LICENSE)

Database GitBackup 是一个自动化的数据库备份解决方案，支持 MySQL 和 PostgreSQL 数据库，它将数据库备份与 Git 版本控制完美结合。该工具可以定期备份指定的数据库，并将备份文件提交到 Git 仓库中，实现备份文件的版本管理和追踪。

## 功能特性

- 🔄 自动定时备份数据库
- 📦 支持多数据库备份
- 🗄️ 支持 MySQL 和 PostgreSQL
- 🔒 使用 gzip 压缩备份文件
- 📊 自动清理过期备份
- 🔍 磁盘空间检查
- 📝 详细的日志记录
- 🐳 Docker 容器化部署
- 🔄 Git 版本控制集成
- 🏥 内置健康检查
- 🌍 支持自定义时区

## 快速开始

### 使用 Docker 运行

```bash
# 基本配置示例
docker run -d \
  --name dbbackup \
  -e DATABASE_URLS="mysql://user:pass@host1:3306/db1,postgres://user:pass@host2:5432/db2" \
  -e GIT_REPO=your-username/your-repo \
  -e GIT_TOKEN=your-github-token \
  -e CRON_SCHEDULE="0 2 * * *" \
  -v /path/to/backup:/backup \
  lff0/dbbackup

# 完整配置示例
docker run -d \
  --name dbbackup \
  -e DATABASE_URLS="mysql://user:pass@host1:3306/db1,postgres://user:pass@host2:5432/db2" \
  -e GIT_REPO=your-username/your-repo \
  -e GIT_TOKEN=your-github-token \
  -e GIT_USER="Backup Bot" \
  -e GIT_EMAIL="backup@example.com" \
  -e CRON_SCHEDULE="0 2 * * *" \
  -e MAX_BACKUPS=30 \
  -e COMPRESSION_LEVEL=9 \
  -e REQUIRED_SPACE=2000 \
  -e TZ=Asia/Shanghai \
  -e BACKUP_ON_START=true \
  -v /path/to/backup:/backup \
  lff0/dbbackup
```

### 本地构建

1. 克隆仓库

```bash
git clone https://github.com/l-ff/dbbackup.git
cd dbbackup
```

2. 构建镜像

```bash
docker build -t dbbackup:latest .
```

3. 运行容器

```bash
# 基本配置示例
docker run -d \
  --name dbbackup \
  -e DATABASE_URLS="mysql://user:pass@host1:3306/db1,postgres://user:pass@host2:5432/db2" \
  -e GIT_REPO=your-username/your-repo \
  -e GIT_TOKEN=your-github-token \
  -e CRON_SCHEDULE="0 2 * * *" \
  -v /path/to/backup:/backup \
  dbbackup:latest

# 完整配置示例
docker run -d \
  --name dbbackup \
  -e DATABASE_URLS="mysql://user:pass@host1:3306/db1,postgres://user:pass@host2:5432/db2" \
  -e GIT_REPO=your-username/your-repo \
  -e GIT_TOKEN=your-github-token \
  -e GIT_USER="Backup Bot" \
  -e GIT_EMAIL="backup@example.com" \
  -e CRON_SCHEDULE="0 2 * * *" \
  -e MAX_BACKUPS=30 \
  -e COMPRESSION_LEVEL=9 \
  -e REQUIRED_SPACE=2000 \
  -e TZ=Asia/Shanghai \
  -e BACKUP_ON_START=true \
  -v /path/to/backup:/backup \
  dbbackup:latest
```

### 环境变量配置

| 变量名            | 描述                                | 默认值           | 是否必需 |
| ----------------- | ----------------------------------- | ---------------- | -------- |
| DATABASE_URLS     | 数据库连接 URL 列表（逗号分隔）     | -                | 是       |
| GIT_REPO          | Git 仓库地址（格式：用户名/仓库名） | -                | 是       |
| GIT_TOKEN         | GitHub 个人访问令牌                 | -                | 是       |
| GIT_USER          | Git 提交用户名                      | AutoSync Bot     | 否       |
| GIT_EMAIL         | Git 提交邮箱                        | autosync@bot.com | 否       |
| CRON_SCHEDULE     | 定时任务计划                        | "0 2 \* \* \*"   | 否       |
| BACKUP_DIR        | 备份文件存储目录                    | /backup          | 否       |
| REPO_DIR          | Git 仓库目录                        | /backup/repo     | 否       |
| MAX_BACKUPS       | 每个数据库保留的最大备份数量        | 10               | 否       |
| COMPRESSION_LEVEL | gzip 压缩级别（1-9）                | 6                | 否       |
| REQUIRED_SPACE    | 所需最小磁盘空间（MB）              | 1000             | 否       |
| TZ                | 时区设置                            | Asia/Shanghai    | 否       |
| BACKUP_ON_START   | 容器启动时是否执行初始备份          | false            | 否       |

### 数据库连接 URL 格式

#### MySQL
```
mysql://username:password@host:port/database
```

#### PostgreSQL
```
postgres://username:password@host:port/database
```

### 配置示例

#### 单个 MySQL 数据库
```
DATABASE_URLS="mysql://root:password@localhost:3306/mydb"
```

#### 单个 PostgreSQL 数据库
```
DATABASE_URLS="postgres://postgres:password@localhost:5432/mydb"
```

#### 多个数据库（混合类型）
```
DATABASE_URLS="mysql://user1:pass1@host1:3306/db1,postgres://user2:pass2@host2:5432/db2"
```

#### 使用特殊字符的密码
如果密码中包含特殊字符，需要进行 URL 编码：
```
DATABASE_URLS="mysql://user:my%40password@host:3306/db"
```

## 备份文件结构

```
/backup/
  └── repo/
      └── database_name/
          ├── backup_20240331_020000.sql.gz
          ├── backup_20240330_020000.sql.gz
          └── ...
```

## 日志

备份日志位于容器内的 `/var/log/cron.log` 文件中，包含详细的备份过程和错误信息。

## 健康检查

容器内置了健康检查机制，每 5 分钟检查一次：

- cron 服务运行状态
- 数据库连接状态（检查所有配置的数据库连接）
- 备份日志文件存在性

## 贡献指南

欢迎提交 Issue 和 Pull Request 来帮助改进这个项目。

## 许可证

本项目采用 MIT 许可证 - 详见 [LICENSE](LICENSE) 文件。

## 作者

- 维护者：lff <dev_lff@outlook.com>
- 项目主页：[GitHub](https://github.com/l-ff/dbbackup)

- 项目主页：[GitHub](https://github.com/l-ff/dbbackup)
