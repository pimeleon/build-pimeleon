# APT Cache Debugging Guide for TrueNAS

## Quick Debug Commands (run on TrueNAS as root)

### 1. Check apt-cacher-ng Status and Logs

```bash
# Check if apt-cacher-ng is running
ps aux | grep apt-cacher-ng

# Check service status (if systemd)
systemctl status apt-cacher-ng

# Real-time log monitoring
tail -f /var/log/apt-cacher-ng/apt-cacher.log
tail -f /var/log/apt-cacher-ng/apt-cacher.err

# Check recent access logs
tail -100 /var/log/apt-cacher-ng/apt-cacher.log | grep -E "(HIT|MISS|GET)"
```

### 2. Monitor Network Activity

```bash
# Monitor connections to port 3142
netstat -tulnp | grep :3142

# Watch active connections
watch 'netstat -an | grep :3142'

# Monitor network traffic on specific interface
tcpdump -i eth0 port 3142 -v

# Real-time connection monitoring
ss -tulnp | grep :3142
```

### 3. Check Cache Statistics via Web Interface

```bash
# Access cache statistics (replace IP with your TrueNAS IP)
curl -s http://192.168.76.5:3142/acng-report.html | grep -E "Total|Hit|Miss|Data"

# Get detailed statistics
wget -O - http://192.168.76.5:3142/acng-report.html 2>/dev/null | html2text | head -50

# Check cache configuration
curl -s http://192.168.76.5:3142/admin/ | grep -A10 -B10 "Configuration"
```

### 4. Examine Cache Directory and Files

```bash
# Check cache directory size and contents
du -sh /var/cache/apt-cacher-ng/
ls -la /var/cache/apt-cacher-ng/

# Check for Debian/Raspbian cache directories
find /var/cache/apt-cacher-ng/ -name "*debian*" -o -name "*raspbian*" | head -20

# Monitor cache directory in real-time
watch 'ls -lat /var/cache/apt-cacher-ng/ | head -10'

# Check disk usage during caching
df -h /var/cache/apt-cacher-ng/
```

### 5. Test Cache Functionality

```bash
# Test direct access from TrueNAS
wget -O /dev/null http://localhost:3142/debian/dists/bookworm/Release
wget -O /dev/null http://localhost:3142/raspbian.raspberrypi.org/raspbian/dists/buster/Release

# Test from your build machine (replace with your machine's IP)
# Run this from your Pimeleon build machine:
# curl -I http://192.168.76.5:3142/debian/dists/bookworm/Release
```

### 6. Check Configuration Files

```bash
# Main configuration
cat /etc/apt-cacher-ng/acng.conf | grep -v ^# | grep -v ^$

# Security configuration  
cat /etc/apt-cacher-ng/security.conf | grep -v ^# | grep -v ^$

# Backend configuration
ls -la /etc/apt-cacher-ng/backends_*

# Check which repositories are configured
grep -r "remap" /etc/apt-cacher-ng/ | grep -v ^#
```

### 7. Debug from Docker Build Container

**From your Pimeleon build machine:**

```bash
# Check if container has proxy configuration
docker exec pimeleon-builder cat /etc/apt/apt.conf.d/01proxy 2>/dev/null || echo "No proxy config found"

# Test connectivity from inside container
docker exec pimeleon-builder curl -I http://192.168.76.5:3142/ 2>/dev/null || echo "Cannot reach cache server"

# Test APT proxy from inside container
docker exec pimeleon-builder apt-get -o Debug::Acquire::http=true update | grep "Proxy"

# Check container's APT configuration
docker exec pimeleon-builder apt-config dump | grep -i proxy

# Test downloading a package through cache
docker exec pimeleon-builder apt-get -o Debug::Acquire::http=true install -y --download-only curl | grep "192.168.76.5"

# Check container's resolv.conf and routing
docker exec pimeleon-builder cat /etc/resolv.conf
docker exec pimeleon-builder ip route

# Test if container can reach cache server directly
docker exec pimeleon-builder telnet 192.168.76.5 3142 <<< 'quit'
```

**Monitor during container build:**

```bash
# Terminal 1: Monitor container build with APT debug
APT_CACHE_SERVER=192.168.76.5 docker compose run --rm -e DEBIAN_FRONTEND=noninteractive builder bash -c "apt-get -o Debug::Acquire::http=true update"

# Terminal 2: Watch docker container logs
docker logs -f pimeleon-builder 2>&1 | grep -E "(192.168.76.5|proxy|cache)"

# Terminal 3: Monitor network from host
sudo tcpdump -i any host 192.168.76.5 and port 3142 -v
```

## Common Issues and Solutions

### Issue: Zero IO Activity Despite Network Traffic

This could indicate:

1. **Proxy passthrough mode** - Cache is forwarding requests without storing
2. **Configuration issue** - Cache directory not writable or misconfigured
3. **Repository not cached** - Some repositories bypass cache

**Debug steps:**

```bash
# Check cache directory permissions
ls -ld /var/cache/apt-cacher-ng/
stat /var/cache/apt-cacher-ng/

# Check if cache is in passthrough mode
grep -i "passthrough" /etc/apt-cacher-ng/acng.conf

# Check repository remapping
grep -E "(Remap|PassThroughPattern)" /etc/apt-cacher-ng/acng.conf
```

### Issue: Cache Not Being Used

**Verify client configuration:**

```bash
# On build machine, check if proxy is configured
docker exec pimeleon-builder cat /etc/apt/apt.conf.d/01proxy

# Test proxy from inside container
docker exec pimeleon-builder curl -I http://192.168.76.5:3142/
```

### Issue: Docker Container Cannot Reach Cache Server

**Check Docker networking:**

```bash
# Test network connectivity from host
ping -c 3 192.168.76.5
telnet 192.168.76.5 3142

# Check Docker bridge network
docker network ls
docker network inspect pimeleon-build_build-network

# Test from container with more verbose output
docker exec pimeleon-builder apt-get -o Debug::Acquire::http=true -o Debug::pkgAcquire::Worker=true update 2>&1 | head -50

# Check if proxy environment variables are set in container
docker exec pimeleon-builder env | grep -i proxy

# Verify container can resolve DNS
docker exec pimeleon-builder nslookup 192.168.76.5 || docker exec pimeleon-builder dig 192.168.76.5
```

### Issue: Build Args Not Passed to Container

**Verify build arguments:**

```bash
# Check if build args were passed correctly
docker image inspect pimeleon-build-builder | jq '.[0].Config.Env' | grep -i cache

# Rebuild container with verbose output
APT_CACHE_SERVER=192.168.76.5 docker compose build --no-cache --progress plain builder

# Check environment variables in running container
docker exec pimeleon-builder env | grep APT_CACHE
```

### Real-Time Debugging During Build

**Terminal 1 (TrueNAS):**

```bash
# Monitor logs in real-time
tail -f /var/log/apt-cacher-ng/apt-cacher.log | grep --line-buffered -E "(GET|HIT|MISS)"
```

**Terminal 2 (TrueNAS):**

```bash
# Monitor cache directory changes
watch 'find /var/cache/apt-cacher-ng/ -mtime -0.01 | head -10'
```

**Terminal 3 (TrueNAS):**

```bash
# Monitor network connections
watch 'netstat -an | grep :3142 | grep ESTABLISHED | wc -l'
```

## Expected Output for Working Cache

When working correctly, you should see:

- **Logs**: `GET` requests followed by either `HIT` (cached) or `MISS` (downloading)
- **Files**: New files appearing in `/var/cache/apt-cacher-ng/debian/` and `/var/cache/apt-cacher-ng/raspbian.raspberrypi.org/`
- **Stats**: Increasing hit ratios in web interface
- **Network**: Initial high activity (downloads), then reduced activity (cache hits)

## Quick Test Command

Run this on TrueNAS to verify cache is working:

```bash
# Clear any existing cache for test
rm -rf /var/cache/apt-cacher-ng/debian/pool/main/h/hello/

# Test download through cache (should create cache files)
wget -O /dev/null http://localhost:3142/debian/pool/main/h/hello/hello_2.12.1-1+b1_amd64.deb

# Check if file was cached
find /var/cache/apt-cacher-ng/ -name "*hello*" -ls
```

## Debug Package Availability Issues

**When packages are not found (like systemd-resolved):**

```bash
# On TrueNAS, check apt-cacher-ng logs for errors
tail -f /var/log/apt-cacher-ng/apt-cacher.log | grep -i "systemd-resolved\|error\|403\|404"

# Check if repository remapping is causing issues
grep -E "(Remap|VfilePattern)" /etc/apt-cacher-ng/acng.conf

# Test direct access to Raspbian package through cache
curl -I "http://localhost:3142/raspbian.raspberrypi.org/raspbian/dists/buster/main/binary-armhf/Packages.gz"

# Check if specific package exists in Raspbian Buster
wget -O - "http://localhost:3142/raspbian.raspberrypi.org/raspbian/dists/buster/main/binary-armhf/Packages.gz" 2>/dev/null | zcat | grep -A5 -B5 "systemd-resolved" || echo "Package not found"

# Compare with direct repository access (bypass cache)
curl -s "http://raspbian.raspberrypi.org/raspbian/dists/buster/main/binary-armhf/Packages.gz" | zcat | grep -A5 -B5 "systemd-resolved" || echo "Package not found in repository"
```

**Test build without cache to isolate issue:**

```bash
# From build machine - test without cache
docker compose run --rm -e RASPBIAN_VERSION=buster builder bash -c "chroot /tmp/test-mount apt-get update && apt-cache search systemd-resolved"

# Compare with cache enabled
APT_CACHE_SERVER=192.168.76.5 docker compose run --rm -e RASPBIAN_VERSION=buster builder bash -c "chroot /tmp/test-mount apt-get update && apt-cache search systemd-resolved"
```
