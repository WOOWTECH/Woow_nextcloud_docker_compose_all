# Changelog

## v33.0.0-v3

### WOOWTECH Fork Changes
- Replaced MariaDB with PostgreSQL 16 for better performance and compatibility
- Removed SSL/HTTPS (HTTP-only for LAN; use Cloudflare Tunnel for external HTTPS)
- Added `db_password` option for configurable PostgreSQL password
- Added Traditional Chinese (zh-Hant) translation
- Added comprehensive Chinese README documentation
- Updated branding to WOOWTECH
- Based on fabio-garavini/hassio-addons nextcloud add-on

### Base
- Nextcloud 33.0.0
- PostgreSQL 16
- Redis (Unix socket)
- LSIO base image (ghcr.io/linuxserver/nextcloud:33.0.0-ls421)
