# Xray Docker - Simplified Proxy Configuration

A **simplified, environment-driven** Xray proxy server that allows you to quickly configure specific domains and IPs to route through proxy with just a few environment variables. No complex JSON configuration required!

## 🎯 Why This Project?

Traditional Xray configuration requires complex JSON files with routing rules, outbound settings, and multiple configuration options. This Docker image simplifies the process:

- **🚀 Quick Setup**: Specify domains/IPs to proxy with simple environment variables
- **⚡ Zero Configuration Files**: No JSON editing - everything via environment variables
- **🔄 Smart Defaults**: Sensible routing rules out of the box
- **🛡️ Private Network Safe**: Automatically routes private IPs directly (no proxy)

**Perfect for**: Users who need to access specific websites or services through a proxy without dealing with complex Xray configurations.

## 🚀 Key Features

- **Environment-Driven Configuration**: Set proxy rules with simple environment variables
- **Dual Mode Support**: SOCKS5 proxy or HTTP proxy with authentication
- **Intelligent Routing**: Automatic private IP detection and smart traffic routing
- **Smart Geodata Updates**: Automatic geoip/geosite database updates with change detection
- **Lightweight**: Alpine-based image with minimal dependencies
- **Graceful Operation**: Connection-aware restart mechanism to minimize service disruption

## 📦 Quick Start

### Common Use Cases

**Want to access Google/YouTube through a proxy?** Just specify:
```bash
-e RULE_PROXY_SITE="geosite:google,geosite:youtube"
```

**Need to route specific IPs through proxy?** Simply set:
```bash
-e RULE_PROXY_IP="8.8.8.8,1.1.1.1"
```

**Everything else routes directly** - no complex configuration needed!

### SOCKS5 Proxy Mode

```bash
docker run -d --name xray-socks \
  --network=host \
  -e MODE=socks \
  -e LOG_LEVEL=warning \
  -e SOCKS_LISTEN_PORT=1080 \
  -e SOCKS_LISTEN_IP=127.0.0.1 \
  -e OUTBOUND_PROTOCOL=freedom \
  -e OUTBOUND_IP=127.0.0.1 \
  -e OUTBOUND_PORT=53 \
  -e RULE_PROXY_SITE="geosite:google" \
  -e RULE_PROXY_IP="geoip:google" \
  your-registry/xray-docker:latest
```

### HTTP Proxy Mode

```bash
docker run -d --name xray-http \
  --network=host \
  -e MODE=http \
  -e LOG_LEVEL=warning \
  -e HTTP_LISTEN_PORT=8080 \
  -e HTTP_LISTEN_IP=127.0.0.1 \
  -e HTTP_ACCOUNTS_JSON='[{"user":"myuser","pass":"mypass"}]' \
  -e OUTBOUND_PROTOCOL=freedom \
  -e OUTBOUND_IP=127.0.0.1 \
  -e OUTBOUND_PORT=53 \
  -e RULE_PROXY_SITE="geosite:google" \
  -e RULE_PROXY_IP="geoip:google" \
  your-registry/xray-docker:latest
```

## ⚙️ Environment Variables

### Required Variables (Common)

These variables are required for both SOCKS and HTTP modes:

| Variable | Description | Example Values |
|----------|-------------|----------------|
| `MODE` | Proxy mode | `socks` or `http` |
| `LOG_LEVEL` | Xray log level | `debug`, `info`, `warning`, `error`, `none` |
| `OUTBOUND_PROTOCOL` | Upstream protocol | `freedom`, `socks`, `http`, `vless`, `vmess`, etc. |
| `OUTBOUND_IP` | Upstream server IP | `127.0.0.1`, `192.168.1.100` |
| `OUTBOUND_PORT` | Upstream server port | `53`, `1080`, `8080` |
| `RULE_PROXY_SITE` | Domain routing rule for proxy | `geosite:google`, `google.com,youtube.com` |
| `RULE_PROXY_IP` | IP routing rule for proxy | `geoip:google`, `8.8.8.8,1.1.1.1` |

### SOCKS Mode Variables

Required when `MODE=socks`:

| Variable | Description | Example Values |
|----------|-------------|----------------|
| `SOCKS_LISTEN_PORT` | SOCKS5 server port | `1080`, `1081` |
| `SOCKS_LISTEN_IP` | SOCKS5 bind address | `127.0.0.1`, `0.0.0.0` |

### HTTP Mode Variables

Required when `MODE=http`:

| Variable | Description | Example Values |
|----------|-------------|----------------|
| `HTTP_LISTEN_PORT` | HTTP proxy server port | `8080`, `8081` |
| `HTTP_LISTEN_IP` | HTTP proxy bind address | `127.0.0.1`, `0.0.0.0` |
| `HTTP_ACCOUNTS_JSON` | Authentication accounts (JSON array) | `[]` (no auth), `[{"user":"u1","pass":"p1"}]` |

#### HTTP_ACCOUNTS_JSON Format

The `HTTP_ACCOUNTS_JSON` must be a valid JSON array:

- **No authentication**: `[]`
- **Single user**: `[{"user":"myuser","pass":"mypass"}]`
- **Multiple users**: `[{"user":"user1","pass":"pass1"},{"user":"user2","pass":"pass2"}]`

### Optional Variables

| Variable | Description | Default | Example Values |
|----------|-------------|---------|----------------|
| `REVERSE_MODE` | Enable reverse routing mode | `0` (disabled) | `0` (normal), `1` (reverse) |
| `RULE_PRIVATE_IP_PROXY` | Route private IPs through proxy in reverse mode | `0` (direct) | `0` (direct), `1` (proxy) |
| `UPDATE_INTERVAL` | Geodata auto-update interval | `0` (disabled) | `6h`, `24h`, `7d`, `3600` (seconds) |
| `GEOSITE_URL` | Custom geosite.dat download URL | GitHub Loyalsoldier repo | Any valid HTTP URL |
| `GEOIP_URL` | Custom geoip.dat download URL | GitHub Loyalsoldier repo | Any valid HTTP URL |
| `SHOW_CONFIG` | Show rendered config at startup | `1` (enabled) | `0` (disabled), `1` (enabled) |

#### Reverse Mode Explained

**Normal Mode (REVERSE_MODE=0)**:
- Private IPs → Direct
- Specified domains/IPs (`RULE_PROXY_SITE`/`RULE_PROXY_IP`) → Proxy
- All other traffic → Direct

**Reverse Mode (REVERSE_MODE=1)**:
- Private IPs → Direct (or Proxy if `RULE_PRIVATE_IP_PROXY=1`)
- Specified domains/IPs (`RULE_PROXY_SITE`/`RULE_PROXY_IP`) → Direct
- All other traffic → Proxy

This is useful when you want most traffic to go through proxy, but certain sites (like local services or CDNs) to go direct.

### XRAY_* Prefix Support

All variables also support `XRAY_` prefix for compatibility:

```bash
# These are equivalent:
-e MODE=socks
-e XRAY_MODE=socks

-e LOG_LEVEL=warning  
-e XRAY_LOG_LEVEL=warning
```

## 🔄 Smart Geodata Updates

The container includes an intelligent geodata update system that minimizes unnecessary service restarts:

### How It Works

1. **Time-based Check**: Only checks for updates after the configured interval
2. **HTTP HEAD Request**: Checks remote file metadata (Last-Modified, ETag) before downloading
3. **Content Hashing**: Compares SHA256 hash to detect actual content changes
4. **Conditional Restart**: Only restarts Xray when files actually change

### Update Intervals

The `UPDATE_INTERVAL` variable supports flexible time formats:

- `3s` - 3 seconds
- `5m` - 5 minutes  
- `2h` - 2 hours
- `7d` - 7 days
- `3600` - 3600 seconds (1 hour)

### Benefits

- **Reduced Service Interruption**: No unnecessary restarts for unchanged files
- **Network Efficiency**: Avoids downloading identical files
- **Connection Preservation**: Smart restart timing based on active connections

## 📋 Complete Examples

### Docker Compose - SOCKS5 Proxy

```yaml
version: '3.8'

services:
  xray-socks:
    image: your-registry/xray-docker:latest
    container_name: xray-socks
    network_mode: host
    restart: unless-stopped
    environment:
      # Required - Mode
      MODE: socks
      
      # Required - Logging
      LOG_LEVEL: warning
      
      # Required - SOCKS Settings
      SOCKS_LISTEN_PORT: 1080
      SOCKS_LISTEN_IP: 127.0.0.1
      
      # Required - Outbound
      OUTBOUND_PROTOCOL: freedom
      OUTBOUND_IP: 127.0.0.1
      OUTBOUND_PORT: 53
      
      # Required - Routing Rules
      RULE_PROXY_SITE: "geosite:google,geosite:youtube,geosite:facebook"
      RULE_PROXY_IP: "geoip:google,geoip:youtube,geoip:facebook"
      
      # Optional - Auto-update every 6 hours
      UPDATE_INTERVAL: 6h
    volumes:
      - ./xray-data:/app/assets
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "1080"]
      interval: 30s
      timeout: 5s
      retries: 3
```

### Docker Compose - HTTP Proxy with Authentication

```yaml
version: '3.8'

services:
  xray-http:
    image: your-registry/xray-docker:latest
    container_name: xray-http
    network_mode: host
    restart: unless-stopped
    environment:
      # Required - Mode
      MODE: http
      
      # Required - Logging
      LOG_LEVEL: info
      
      # Required - HTTP Settings
      HTTP_LISTEN_PORT: 8080
      HTTP_LISTEN_IP: 0.0.0.0
      HTTP_ACCOUNTS_JSON: '[{"user":"admin","pass":"secretpass"},{"user":"user1","pass":"pass123"}]'
      
      # Required - Outbound (to upstream SOCKS proxy)
      OUTBOUND_PROTOCOL: socks
      OUTBOUND_IP: upstream-proxy.example.com
      OUTBOUND_PORT: 1080
      
      # Required - Routing Rules
      RULE_PROXY_SITE: "geosite:geolocation-!cn"
      RULE_PROXY_IP: "geoip:geolocation-!cn"
      
      # Optional - Daily updates
      UPDATE_INTERVAL: 24h
    volumes:
      - ./xray-data:/app/assets
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "8080"]
      interval: 30s
      timeout: 5s
      retries: 3
```

### Reverse Mode Configuration - Global Proxy with Exceptions

```yaml
version: '3.8'

services:
  xray-reverse:
    image: your-registry/xray-docker:latest
    container_name: xray-reverse
    network_mode: host
    restart: unless-stopped
    environment:
      MODE: socks
      LOG_LEVEL: warning
      
      # SOCKS5 Settings
      SOCKS_LISTEN_PORT: 1080
      SOCKS_LISTEN_IP: 127.0.0.1
      
      # Upstream proxy
      OUTBOUND_PROTOCOL: socks
      OUTBOUND_IP: upstream-proxy.example.com
      OUTBOUND_PORT: 1080
      
      # Enable reverse mode - everything goes through proxy except specified sites/IPs
      REVERSE_MODE: 1
      
      # Specify sites/IPs that should go DIRECT (bypassing proxy)
      RULE_PROXY_SITE: "geosite:cn,example.com,local-service.internal"
      RULE_PROXY_IP: "geoip:cn,192.168.1.100,10.0.0.5"
      
      # Optional - force private IPs through proxy too (useful for VPN scenarios)
      # RULE_PRIVATE_IP_PROXY: 1
      
      # Auto-update
      UPDATE_INTERVAL: 12h
    volumes:
      - ./xray-data:/app/assets
    healthcheck:
      test: ["CMD", "nc", "-z", "127.0.0.1", "1080"]
      interval: 30s
      timeout: 5s
      retries: 3
```

### Advanced Configuration - Chain Proxying

```yaml
version: '3.8'

services:
  xray-chain:
    image: your-registry/xray-docker:latest
    container_name: xray-chain
    network_mode: host
    restart: unless-stopped
    environment:
      MODE: socks
      LOG_LEVEL: debug
      
      # Listen on specific interface
      SOCKS_LISTEN_PORT: 1080
      SOCKS_LISTEN_IP: 192.168.1.100
      
      # Chain through upstream HTTP proxy
      OUTBOUND_PROTOCOL: http
      OUTBOUND_IP: upstream-http-proxy.internal
      OUTBOUND_PORT: 3128
      
      # Complex routing rules
      RULE_PROXY_SITE: "geosite:category-ads-all,geosite:google,geosite:github"
      RULE_PROXY_IP: "geoip:cloudflare,geoip:google,1.1.1.1,8.8.8.8"
      
      # Frequent updates for testing
      UPDATE_INTERVAL: 1h
      
      # Custom geodata sources
      GEOSITE_URL: "https://custom-cdn.example.com/geosite.dat"
      GEOIP_URL: "https://custom-cdn.example.com/geoip.dat"
      
      # Disable config output in logs
      SHOW_CONFIG: 0
    volumes:
      - ./xray-data:/app/assets
```

## 🛠️ Building

Build the Docker image:

```bash
# Build with default Xray version
docker build -t xray-docker .

# Build with specific Xray version
docker build --build-arg XRAY_REF=v1.8.23 -t xray-docker:v1.8.23 .
```

## 📝 Logs

The container logs to stdout/stderr. Use standard Docker logging:

```bash
# View logs
docker logs xray-socks

# Follow logs
docker logs -f xray-socks

# Show only error logs
docker logs xray-socks 2>&1 | grep ERROR
```

## 🔧 Troubleshooting

### Common Issues

1. **Permission Denied**
   - Ensure the container has proper network permissions
   - Check if ports are available and not in use

2. **Geodata Download Failures**
   - Verify internet connectivity from container
   - Check custom `GEOSITE_URL`/`GEOIP_URL` if specified
   - Review update logs: `docker logs container-name | grep geodata`

3. **Configuration Errors**
   - Set `SHOW_CONFIG=1` to see rendered configuration
   - Validate JSON format for `HTTP_ACCOUNTS_JSON`
   - Ensure all required variables are set

### Health Checks

The container doesn't expose ports by default (uses host network). Implement health checks using netcat:

```bash
# Test SOCKS5 port
nc -z 127.0.0.1 1080

# Test HTTP proxy port  
nc -z 127.0.0.1 8080
```

## 📄 License

This project follows the same license as Xray-core.

## 🤝 Contributing

Contributions welcome! Please read the entrypoint.sh script to understand the configuration logic before making changes.
