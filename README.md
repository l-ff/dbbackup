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
  -e GIT_REPO=your-username/your-repo \
  -e GIT_TOKEN=your-github-token \
  -e CRON_SCHEDULE="0 2 * * *" \
  -e DATABASE_CONFIG_FILE=my-db-config.txt \
  -v /path/to/backup:/backup \
  lff0/dbbackup

# 完整配置示例
docker run -d \
  --name dbbackup \
  -e GIT_REPO=your-username/your-repo \
  -e GIT_TOKEN=your-github-token \
  -e GIT_USER="Backup Bot" \
  -e GIT_EMAIL="backup@example.com" \
  -e DATABASE_CONFIG_FILE=my-db-config.txt \
  -e CRON_SCHEDULE="0 2 * * *" \
  -e MAX_BACKUPS=30 \
  -e COMPRESSION_LEVEL=9 \
  -e REQUIRED_SPACE=2000 \
  -e TZ=Asia/Shanghai \
  -e BACKUP_ON_START=true \
  -v /path/to/backup:/backup \
  lff0/dbbackup
```

### 数据库连接配置

数据库连接配置通过 Git 仓库中的配置文件管理。默认使用 `database_urls.txt` 文件，您可以通过设置 `DATABASE_CONFIG_FILE` 环境变量来自定义配置文件名称。当容器首次启动时，会自动创建此文件并推送到仓库。您需要编辑此文件添加数据库连接信息，然后重启容器。

#### 数据库连接字符串文件格式

在 Git 仓库中配置数据库连接（以下以默认的 `database_urls.txt` 为例）：

```txt
# 每行一个数据库连接字符串
# MySQL 示例
mysql://user1:pass1@host1:3306/db1
mysql://backup:pass123@localhost:3306/wordpress
mysql://root:complex-pass@mysql.example.com:3306/shop

# PostgreSQL 示例
postgres://user2:pass2@host2:5432/db2
postgres://postgres:pass456@localhost:5432/blog
postgres://admin:secure-pass@pg.example.com:5432/analytics

# 带特殊字符的密码示例
mysql://user:my%40complex%23pass@host:3306/db
postgres://user:pass%26word%23123@host:5432/db

# 不同环境的数据库
# 测试环境
mysql://test_user:test123@test.mysql:3306/testdb
# 生产环境
mysql://prod_user:prod123@prod.mysql:3306/proddb
```

注意事项：
- 每行一个数据库连接字符串
- 以 # 开头的行被视为注释
- 空行会被忽略
- 支持同时配置多个数据库
- 支持混合使用 MySQL 和 PostgreSQL
- 可以通过 DATABASE_CONFIG_FILE 环境变量自定义配置文件名称
- 密码中的特殊字符需要进行 URL 编码
- 建议使用注释对不同环境或用途的数据库进行分组
- 建议将配置文件中的敏感信息（如密码）替换为环境变量或使用密钥管理服务

### 环境变量配置

所有环境变量的默认值都在 Dockerfile 中定义。

| 变量名              | 描述                                | 是否必需 |
| ------------------ | ----------------------------------- | -------- |
| GIT_REPO          | Git 仓库地址（格式：用户名/仓库名）   | 是       |
| GIT_TOKEN         | GitHub 个人访问令牌                  | 是       |
| GIT_USER          | Git 提交用户名                       | 否       |
| GIT_EMAIL         | Git 提交邮箱                         | 否       |
| DATABASE_CONFIG_FILE | 数据库配置文件名称                  | 否       |
| CRON_SCHEDULE     | 定时任务计划                         | 否       |
| BACKUP_DIR        | 备份文件存储目录                     | 否       |
| REPO_DIR          | Git 仓库目录                         | 否       |
| BACKUP_LOG        | 备份日志文件路径                     | 否       |
| MAX_BACKUPS       | 每个数据库保留的最大备份数量         | 否       |
| COMPRESSION_LEVEL | gzip 压缩级别（1-9）                 | 否       |
| REQUIRED_SPACE    | 所需最小磁盘空间（MB）               | 否       |
| TZ                | 时区设置                             | 否       |
| BACKUP_ON_START   | 容器启动时是否执行初始备份           | 否       |

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
mysql://root:password@localhost:3306/mydb
```

#### 单个 PostgreSQL 数据库
```
postgres://postgres:password@localhost:5432/mydb
```

#### 多个数据库（混合类型）
```
mysql://user1:pass1@host1:3306/db1
postgres://user2:pass2@host2:5432/db2
```

#### 使用特殊字符的密码
如果密码中包含特殊字符，需要进行 URL 编码：
```
mysql://user:my%40password@host:3306/db
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

## 数据库还原

### 还原步骤

1. **下载备份文件**
   - 从 Git 仓库中下载需要还原的备份文件（.sql.gz 格式）
   - 使用 `git clone` 或直接从 GitHub 网页下载

2. **解压备份文件**
   ```bash
   # 解压 .sql.gz 文件
   gunzip backup_20240331_020000.sql.gz
   ```

3. **还原数据库**

   #### MySQL 数据库还原
   ```bash
   # 方法 1：使用 mysql 命令行
   mysql -u username -p database_name < backup_20240331_020000.sql

   # 方法 2：使用 mysqlimport
   mysqlimport -u username -p database_name backup_20240331_020000.sql
   ```

   #### PostgreSQL 数据库还原
   ```bash
   # 方法 1：使用 psql 命令行
   psql -U username -d database_name < backup_20240331_020000.sql

   # 方法 2：使用 pg_restore（如果备份是自定义格式）
   pg_restore -U username -d database_name backup_20240331_020000.sql
   ```

### 还原注意事项

- 还原前请确保目标数据库已创建
- 确保有足够的磁盘空间
- 建议在还原前备份目标数据库
- 还原过程中请勿中断操作
- 对于大型数据库，建议在低峰期进行还原
- 还原后检查数据库完整性和一致性

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
