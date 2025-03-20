#!/bin/bash

# Check if script is run as root, if not elevate
if [ "$(id -u)" -ne 0 ]; then
    echo "This script needs to be run as root. Elevating privileges..."
    exec sudo -s "$0" "$@"
    exit $?
fi

echo "================================================================"
echo "Installing Docker..."
echo "================================================================"
curl -fsSL https://get.docker.com | sh

echo "================================================================"
echo "Installing Tailscale..."
echo "================================================================"
curl -fsSL https://tailscale.com/install.sh | sh

# Prompt for auth key
echo "================================================================"
read -p "Enter Tailscale auth key: " AUTH_KEY
echo "================================================================"

# Start Tailscale with SSH enabled
echo "Starting Tailscale with SSH enabled..."
tailscale up --auth-key="$AUTH_KEY" --ssh

# Wait for Tailscale to fully initialize
echo "Waiting for Tailscale to initialize..."
sleep 5

# Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)
if [ -z "$TAILSCALE_IP" ]; then
    echo "Error: Failed to get Tailscale IP. Please check Tailscale status."
    exit 1
fi
echo "Tailscale IP: $TAILSCALE_IP"

# Configure Docker to bind to Tailscale interface
echo "Configuring Docker to bind to Tailscale interface..."

# Create Docker daemon configuration directory if it doesn't exist
mkdir -p /etc/docker

# Create or update Docker daemon configuration
cat > /etc/docker/daemon.json <<EOF
{
  "hosts": ["unix:///var/run/docker.sock", "tcp://${TAILSCALE_IP}:2375"],
  "tls": false
}
EOF

# Create systemd override directory
mkdir -p /etc/systemd/system/docker.service.d

# Create override file
cat > /etc/systemd/system/docker.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd
EOF

# Reload systemd, restart Docker
systemctl daemon-reload
systemctl restart docker

# Verify Docker is running
if systemctl is-active --quiet docker; then
    echo "================================================================"
    echo "Setup completed successfully!"
    echo "Docker is now bound to Tailscale IP: ${TAILSCALE_IP}:2375"
    echo "You can connect to Docker using: docker -H tcp://${TAILSCALE_IP}:2375 info"
    echo "================================================================"
else
    echo "================================================================"
    echo "Error: Docker failed to restart. Please check Docker status."
    echo "================================================================"
    exit 1
fi

# Show Tailscale status
echo "Tailscale status:"
tailscale status

exit 0
