# Nextcloud - K3s/Kubernetes 部署指南

[English](#english) | [中文](#中文)

---

## English

### Overview

Self-hosted cloud storage, file sync, sharing, and collaboration platform. Nextcloud is a Google Drive / Dropbox alternative that gives you full control over your data. This deployment includes PostgreSQL with pgvector for AI-powered search, Redis for session caching and file locking, and a dedicated cron container for background task processing.

> **GitHub Repo (Podman/Docker):** [Woow_nextcloud_docker_compose_all](https://github.com/WOOWTECH/Woow_nextcloud_docker_compose_all)

### Architecture

```
                         ┌──────────────────────────────────────────────────┐
                         │                K3s / Kubernetes                  │
                         │                                                  │
  ┌───────────┐          │  ┌──────────────────────────────────────────┐    │
  │  Browser   │  :18080  │  │         Namespace: nextcloud             │    │
  │           ├──────────►│  │                                          │    │
  └───────────┘  NodePort │  │  ┌───────────┐    ┌──────────────────┐  │    │
                         │  │  │  Service   │    │   Deployment     │  │    │
                         │  │  │ nextcloud  ├───►│   nextcloud      │  │    │
                         │  │  │ :80        │    │  (nextcloud:     │  │    │
                         │  │  └───────────┘    │   stable)        │  │    │
                         │  │                    │  [PVC: 5Gi html] │  │    │
                         │  │                    │  [PVC: 50Gi data]│  │    │
                         │  │                    └──┬──────┬───┘    │  │    │
                         │  │                       │      │        │  │    │
                         │  │              ┌────────┘      └──────┐ │  │    │
                         │  │              ▼                      ▼ │  │    │
                         │  │  ┌───────────────────┐  ┌──────────┐ │  │    │
                         │  │  │  StatefulSet      │  │Deployment│ │  │    │
                         │  │  │  db (pgvector/    │  │ redis    │ │  │    │
                         │  │  │  pgvector:pg16)   │  │ (redis:  │ │  │    │
                         │  │  │  :5432            │  │  alpine) │ │  │    │
                         │  │  │  [PVC: 10Gi]      │  │ :6379    │ │  │    │
                         │  │  └───────────────────┘  │[PVC:1Gi] │ │  │    │
                         │  │                          └──────────┘ │  │    │
                         │  │                                       │  │    │
                         │  │  ┌──────────────────┐                 │  │    │
                         │  │  │   Deployment     │                 │  │    │
                         │  │  │   cron           │  (shares html   │  │    │
                         │  │  │  (nextcloud:     │   & data PVCs)  │  │    │
                         │  │  │   stable)        │                 │  │    │
                         │  │  └──────────────────┘                 │  │    │
                         │  │                                       │  │    │
                         │  └──────────────────────────────────────────┘    │
                         └──────────────────────────────────────────────────┘

  Port Mappings:
    External :18080  ──►  Service :80  ──►  Pod nextcloud :80
    Internal :5432   ──►  Pod db (PostgreSQL + pgvector) :5432
    Internal :6379   ──►  Pod redis :6379
```

### Features

- Self-hosted file sync, sharing, and collaboration (Google Drive alternative)
- PostgreSQL with pgvector extension for AI-powered vector search
- Redis for session caching, file locking, and transactional locking
- Dedicated cron container for background task processing (file scans, cleanup)
- Supports up to 16GB file uploads via PHP configuration
- HTTPS-ready with `OVERWRITEPROTOCOL` for reverse proxy setups
- Automatic admin account creation on first deployment

### Quick Start

```bash
# 1. Update secrets before deploying
nano k8s-manifests/nextcloud/secret.yaml

# 2. Deploy all Nextcloud components
kubectl apply -k k8s-manifests/nextcloud/

# 3. Verify pods are running
kubectl -n nextcloud get pods

# 4. Watch logs for initial setup
kubectl -n nextcloud logs deploy/nextcloud -f
```

### Configuration

#### Environment Variables

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `POSTGRES_DB` | PostgreSQL database name | `nextcloud` | Yes |
| `POSTGRES_USER` | PostgreSQL username | `nextcloud` | Yes |
| `POSTGRES_HOST` | PostgreSQL hostname | `db` | Yes |
| `REDIS_HOST` | Redis hostname | `redis` | Yes |
| `REDIS_HOST_PORT` | Redis port | `6379` | Yes |
| `OVERWRITEPROTOCOL` | Protocol for URL generation (set to `https` behind reverse proxy) | `https` | No |
| `NEXTCLOUD_TRUSTED_DOMAINS` | Space-separated list of trusted domains | `nextcloud.local` | Yes |
| `PHP_MEMORY_LIMIT` | PHP memory limit | `512M` | No |
| `PHP_UPLOAD_LIMIT` | Maximum upload file size | `16G` | No |

#### Secrets

Edit `secret.yaml` before deploying:

| Secret Key | Description | Default (change me!) |
|------------|-------------|----------------------|
| `POSTGRES_PASSWORD` | PostgreSQL password | `changeme-postgres-password` |
| `NEXTCLOUD_ADMIN_USER` | Nextcloud admin username | `admin` |
| `NEXTCLOUD_ADMIN_PASSWORD` | Nextcloud admin password | `changeme-admin-password` |

```bash
# Edit the secret file
nano k8s-manifests/nextcloud/secret.yaml

# Or generate a strong password
openssl rand -base64 32
```

### Accessing the Service

| Endpoint | URL | Protocol |
|----------|-----|----------|
| Nextcloud Web UI | `http://<node-ip>:18080` | HTTP (NodePort) |
| Internal (cluster) | `http://nextcloud.nextcloud.svc.cluster.local:80` | HTTP |

After first access, the admin account is created automatically using the credentials from `secret.yaml`.

### Data Persistence

| PVC Name | Mount Path | Size | Purpose |
|----------|------------|------|---------|
| `postgres-data` | `/var/lib/postgresql/data` | 10Gi | PostgreSQL database files |
| `redis-data` | `/data` | 1Gi | Redis AOF persistence |
| `nextcloud-html` | `/var/www/html` | 5Gi | Nextcloud application files, config, themes |
| `nextcloud-data` | `/var/www/html/data` | 50Gi | User files and uploads |

All PVCs use the `local-path` storage class (k3s default).

### Backup & Restore

#### Backup

```bash
# 1. Put Nextcloud into maintenance mode
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ maintenance:mode --on"

# 2. Backup PostgreSQL database
kubectl -n nextcloud exec sts/db -- pg_dump -U nextcloud nextcloud > nextcloud-db-backup.sql

# 3. Backup user data
kubectl -n nextcloud exec deploy/nextcloud -- tar czf /tmp/data-backup.tar.gz /var/www/html/data
kubectl -n nextcloud cp nextcloud/<nextcloud-pod>:/tmp/data-backup.tar.gz ./data-backup.tar.gz

# 4. Disable maintenance mode
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ maintenance:mode --off"
```

#### Restore

```bash
# 1. Restore database
kubectl -n nextcloud exec -i sts/db -- psql -U nextcloud nextcloud < nextcloud-db-backup.sql

# 2. Restore user data
kubectl -n nextcloud cp ./data-backup.tar.gz nextcloud/<nextcloud-pod>:/tmp/data-backup.tar.gz
kubectl -n nextcloud exec deploy/nextcloud -- tar xzf /tmp/data-backup.tar.gz -C /

# 3. Rescan files
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ files:scan --all"
```

### Useful Commands

```bash
# Check all resources in the namespace
kubectl -n nextcloud get all

# View real-time Nextcloud logs
kubectl -n nextcloud logs deploy/nextcloud -f

# Run occ commands (Nextcloud CLI)
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ status"

# List installed apps
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ app:list"

# Restart Nextcloud
kubectl -n nextcloud rollout restart deploy/nextcloud

# Manually trigger cron
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php -f /var/www/html/cron.php"

# Delete and redeploy
kubectl delete -k k8s-manifests/nextcloud/
kubectl apply -k k8s-manifests/nextcloud/
```

### Troubleshooting

#### Nextcloud stuck in maintenance mode

```bash
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ maintenance:mode --off"
```

#### Database connection refused

```bash
# Check if PostgreSQL is ready
kubectl -n nextcloud get pods -l component=db
kubectl -n nextcloud logs sts/db

# Verify the service is reachable
kubectl -n nextcloud exec deploy/nextcloud -- nc -zv db 5432
```

#### Cron jobs not running

```bash
# Check cron pod status
kubectl -n nextcloud get pods -l component=cron
kubectl -n nextcloud logs deploy/cron

# Manually trigger cron
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php -f /var/www/html/cron.php"
```

#### Trusted domain error

If you see "Access through untrusted domain", update the `NEXTCLOUD_TRUSTED_DOMAINS` value in `configmap.yaml` and re-apply:

```bash
kubectl apply -k k8s-manifests/nextcloud/
kubectl -n nextcloud rollout restart deploy/nextcloud
```

#### Redis connection issues

```bash
kubectl -n nextcloud get pods -l component=redis
kubectl -n nextcloud exec deploy/redis -- redis-cli ping
```

### File Structure

```
k8s-manifests/nextcloud/
├── kustomization.yaml          # Kustomize entry point
├── namespace.yaml              # Namespace: nextcloud
├── configmap.yaml              # Environment variables (domains, PHP limits)
├── secret.yaml                 # Database & admin passwords
├── db-deployment.yaml          # PostgreSQL 16 + pgvector StatefulSet
├── db-service.yaml             # ClusterIP service for PostgreSQL
├── redis-deployment.yaml       # Redis Alpine Deployment
├── redis-service.yaml          # ClusterIP service for Redis
├── nextcloud-deployment.yaml   # Nextcloud Deployment with init containers
├── nextcloud-service.yaml      # NodePort service (18080)
├── cron-deployment.yaml        # Cron Deployment for background tasks
├── pvc.yaml                    # PVCs for all data volumes
└── README.md                   # This file
```

---

## 中文

### 概述

自架雲端儲存、檔案同步、共享與協作平台。Nextcloud 是 Google Drive / Dropbox 的替代方案，讓您完全掌控自己的資料。此部署包含具有 pgvector 擴充的 PostgreSQL 以支援 AI 驅動搜尋、Redis 用於工作階段快取與檔案鎖定，以及專用的 cron 容器用於背景工作處理。

> **GitHub 儲存庫 (Podman/Docker):** [Woow_nextcloud_docker_compose_all](https://github.com/WOOWTECH/Woow_nextcloud_docker_compose_all)

### 架構圖

```
                         ┌──────────────────────────────────────────────────┐
                         │                K3s / Kubernetes                  │
                         │                                                  │
  ┌───────────┐          │  ┌──────────────────────────────────────────┐    │
  │   瀏覽器   │  :18080  │  │       命名空間: nextcloud                │    │
  │           ├──────────►│  │                                          │    │
  └───────────┘  NodePort │  │  ┌───────────┐    ┌──────────────────┐  │    │
                         │  │  │  Service   │    │   Deployment     │  │    │
                         │  │  │ nextcloud  ├───►│   nextcloud      │  │    │
                         │  │  │ :80        │    │  (nextcloud:     │  │    │
                         │  │  └───────────┘    │   stable)        │  │    │
                         │  │                    │  [PVC: 5Gi html] │  │    │
                         │  │                    │  [PVC: 50Gi data]│  │    │
                         │  │                    └──┬──────┬───┘    │  │    │
                         │  │                       │      │        │  │    │
                         │  │              ┌────────┘      └──────┐ │  │    │
                         │  │              ▼                      ▼ │  │    │
                         │  │  ┌───────────────────┐  ┌──────────┐ │  │    │
                         │  │  │  StatefulSet      │  │Deployment│ │  │    │
                         │  │  │  db (pgvector/    │  │ redis    │ │  │    │
                         │  │  │  pgvector:pg16)   │  │ (redis:  │ │  │    │
                         │  │  │  :5432            │  │  alpine) │ │  │    │
                         │  │  │  [PVC: 10Gi]      │  │ :6379    │ │  │    │
                         │  │  └───────────────────┘  │[PVC:1Gi] │ │  │    │
                         │  │                          └──────────┘ │  │    │
                         │  │                                       │  │    │
                         │  │  ┌──────────────────┐                 │  │    │
                         │  │  │   Deployment     │                 │  │    │
                         │  │  │   cron           │（共用 html      │  │    │
                         │  │  │  (nextcloud:     │  與 data PVC）  │  │    │
                         │  │  │   stable)        │                 │  │    │
                         │  │  └──────────────────┘                 │  │    │
                         │  │                                       │  │    │
                         │  └──────────────────────────────────────────┘    │
                         └──────────────────────────────────────────────────┘

  連接埠對應:
    外部 :18080  ──►  Service :80  ──►  Pod nextcloud :80
    內部 :5432   ──►  Pod db (PostgreSQL + pgvector) :5432
    內部 :6379   ──►  Pod redis :6379
```

### 功能特色

- 自架檔案同步、共享與協作平台（Google Drive 替代方案）
- PostgreSQL 搭配 pgvector 擴充，支援 AI 驅動向量搜尋
- Redis 用於工作階段快取、檔案鎖定與交易鎖定
- 專用 cron 容器處理背景工作（檔案掃描、清理）
- 透過 PHP 組態支援最大 16GB 檔案上傳
- 搭配 `OVERWRITEPROTOCOL` 支援反向代理的 HTTPS 設定
- 首次部署時自動建立管理員帳號

### 快速開始

```bash
# 1. 部署前更新密鑰設定
nano k8s-manifests/nextcloud/secret.yaml

# 2. 部署所有 Nextcloud 元件
kubectl apply -k k8s-manifests/nextcloud/

# 3. 確認 Pod 正常運行
kubectl -n nextcloud get pods

# 4. 監看初始設定日誌
kubectl -n nextcloud logs deploy/nextcloud -f
```

### 設定

#### 環境變數

| 變數 | 說明 | 預設值 | 必填 |
|------|------|--------|------|
| `POSTGRES_DB` | PostgreSQL 資料庫名稱 | `nextcloud` | 是 |
| `POSTGRES_USER` | PostgreSQL 使用者名稱 | `nextcloud` | 是 |
| `POSTGRES_HOST` | PostgreSQL 主機名稱 | `db` | 是 |
| `REDIS_HOST` | Redis 主機名稱 | `redis` | 是 |
| `REDIS_HOST_PORT` | Redis 連接埠 | `6379` | 是 |
| `OVERWRITEPROTOCOL` | URL 產生協定（反向代理後設為 `https`） | `https` | 否 |
| `NEXTCLOUD_TRUSTED_DOMAINS` | 以空格分隔的信任網域清單 | `nextcloud.local` | 是 |
| `PHP_MEMORY_LIMIT` | PHP 記憶體限制 | `512M` | 否 |
| `PHP_UPLOAD_LIMIT` | 最大上傳檔案大小 | `16G` | 否 |

#### 密鑰設定

部署前請編輯 `secret.yaml`：

| 密鑰名稱 | 說明 | 預設值（請更改！） |
|----------|------|-------------------|
| `POSTGRES_PASSWORD` | PostgreSQL 密碼 | `changeme-postgres-password` |
| `NEXTCLOUD_ADMIN_USER` | Nextcloud 管理員帳號 | `admin` |
| `NEXTCLOUD_ADMIN_PASSWORD` | Nextcloud 管理員密碼 | `changeme-admin-password` |

```bash
# 編輯密鑰檔案
nano k8s-manifests/nextcloud/secret.yaml

# 或產生強密碼
openssl rand -base64 32
```

### 存取服務

| 端點 | URL | 協定 |
|------|-----|------|
| Nextcloud 網頁介面 | `http://<節點IP>:18080` | HTTP (NodePort) |
| 內部（叢集） | `http://nextcloud.nextcloud.svc.cluster.local:80` | HTTP |

首次存取時，系統會使用 `secret.yaml` 中的帳號密碼自動建立管理員帳號。

### 資料持久化

| PVC 名稱 | 掛載路徑 | 大小 | 用途 |
|----------|----------|------|------|
| `postgres-data` | `/var/lib/postgresql/data` | 10Gi | PostgreSQL 資料庫檔案 |
| `redis-data` | `/data` | 1Gi | Redis AOF 持久化 |
| `nextcloud-html` | `/var/www/html` | 5Gi | Nextcloud 應用程式檔案、設定、佈景主題 |
| `nextcloud-data` | `/var/www/html/data` | 50Gi | 使用者檔案與上傳資料 |

所有 PVC 使用 `local-path` 儲存類別（k3s 預設）。

### 備份與還原

#### 備份

```bash
# 1. 將 Nextcloud 設為維護模式
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ maintenance:mode --on"

# 2. 備份 PostgreSQL 資料庫
kubectl -n nextcloud exec sts/db -- pg_dump -U nextcloud nextcloud > nextcloud-db-backup.sql

# 3. 備份使用者資料
kubectl -n nextcloud exec deploy/nextcloud -- tar czf /tmp/data-backup.tar.gz /var/www/html/data
kubectl -n nextcloud cp nextcloud/<nextcloud-pod>:/tmp/data-backup.tar.gz ./data-backup.tar.gz

# 4. 關閉維護模式
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ maintenance:mode --off"
```

#### 還原

```bash
# 1. 還原資料庫
kubectl -n nextcloud exec -i sts/db -- psql -U nextcloud nextcloud < nextcloud-db-backup.sql

# 2. 還原使用者資料
kubectl -n nextcloud cp ./data-backup.tar.gz nextcloud/<nextcloud-pod>:/tmp/data-backup.tar.gz
kubectl -n nextcloud exec deploy/nextcloud -- tar xzf /tmp/data-backup.tar.gz -C /

# 3. 重新掃描檔案
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ files:scan --all"
```

### 實用指令

```bash
# 檢視命名空間中的所有資源
kubectl -n nextcloud get all

# 即時檢視 Nextcloud 日誌
kubectl -n nextcloud logs deploy/nextcloud -f

# 執行 occ 指令（Nextcloud CLI）
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ status"

# 列出已安裝的應用程式
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ app:list"

# 重啟 Nextcloud
kubectl -n nextcloud rollout restart deploy/nextcloud

# 手動觸發 cron
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php -f /var/www/html/cron.php"

# 刪除並重新部署
kubectl delete -k k8s-manifests/nextcloud/
kubectl apply -k k8s-manifests/nextcloud/
```

### 疑難排解

#### Nextcloud 卡在維護模式

```bash
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php occ maintenance:mode --off"
```

#### 資料庫連線被拒絕

```bash
# 檢查 PostgreSQL 是否就緒
kubectl -n nextcloud get pods -l component=db
kubectl -n nextcloud logs sts/db

# 驗證服務是否可達
kubectl -n nextcloud exec deploy/nextcloud -- nc -zv db 5432
```

#### Cron 工作未執行

```bash
# 檢查 cron Pod 狀態
kubectl -n nextcloud get pods -l component=cron
kubectl -n nextcloud logs deploy/cron

# 手動觸發 cron
kubectl -n nextcloud exec deploy/nextcloud -- su -s /bin/bash www-data -c "php -f /var/www/html/cron.php"
```

#### 信任網域錯誤

如果出現「Access through untrusted domain」錯誤，請更新 `configmap.yaml` 中的 `NEXTCLOUD_TRUSTED_DOMAINS` 值並重新套用：

```bash
kubectl apply -k k8s-manifests/nextcloud/
kubectl -n nextcloud rollout restart deploy/nextcloud
```

#### Redis 連線問題

```bash
kubectl -n nextcloud get pods -l component=redis
kubectl -n nextcloud exec deploy/redis -- redis-cli ping
```

### 檔案結構

```
k8s-manifests/nextcloud/
├── kustomization.yaml          # Kustomize 進入點
├── namespace.yaml              # 命名空間: nextcloud
├── configmap.yaml              # 環境變數（網域、PHP 限制）
├── secret.yaml                 # 資料庫與管理員密碼
├── db-deployment.yaml          # PostgreSQL 16 + pgvector StatefulSet
├── db-service.yaml             # PostgreSQL ClusterIP 服務
├── redis-deployment.yaml       # Redis Alpine Deployment
├── redis-service.yaml          # Redis ClusterIP 服務
├── nextcloud-deployment.yaml   # Nextcloud Deployment（含 init 容器）
├── nextcloud-service.yaml      # NodePort 服務（18080）
├── cron-deployment.yaml        # 背景工作 Cron Deployment
├── pvc.yaml                    # 所有資料卷的 PVC
└── README.md                   # 本文件
```
