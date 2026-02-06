# ngrok Remote Access

ngrok provides secure tunnels to access your Pi from the internet.

## Initial Setup

1. Get your authtoken from <https://dashboard.ngrok.com/get-started/your-authtoken>

2. Configure ngrok:

   ```bash
   sudo -u pim-ngrok ngrok config add-authtoken YOUR_AUTHTOKEN --config /var/lib/ngrok/ngrok.yml
   ```

3. Enable and start the service:

   ```bash
   sudo systemctl unmask ngrok
   sudo systemctl enable --now ngrok
   ```

## Check Tunnel URL

Once running, get your public URL:

```bash
curl -s localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url'
```

## Service Management

```bash
sudo systemctl status ngrok    # Check status
sudo systemctl restart ngrok   # Restart tunnel
sudo journalctl -u ngrok -f    # View logs
```

## Configuration

Config file: `/var/lib/ngrok/ngrok.yml`

Example for SSH tunnel:

```yaml
version: "2"
authtoken: YOUR_AUTHTOKEN
tunnels:
  ssh:
    proto: tcp
    addr: 22
```

Then update service: edit `/etc/systemd/system/ngrok.service` and change:

```ini
ExecStart=/usr/local/bin/ngrok start --all --config /var/lib/ngrok/ngrok.yml
```
