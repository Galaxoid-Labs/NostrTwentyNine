#!/bin/bash

set -e

# Function to display ASCII header
display_header() {
    cat << "EOF"
    _   __           __      ______                    __        _   ___
   / | / /___  _____/ /_____/_  __/      _____  ____  / /___  __/ | / (_)___  ___
  /  |/ / __ \/ ___/ __/ ___// / | | /| / / _ \/ __ \/ __/ / / /  |/ / / __ \/ _ \
 / /|  / /_/ (__  ) /_/ /   / /  | |/ |/ /  __/ / / / /_/ /_/ / /|  / / / / /  __/
/_/ |_/\____/____/\__/_/   /_/   |__/|__/\___/_/ /_/\__/\__, /_/ |_/_/_/ /_/\___/
                                                       /____/
EOF
    echo
    echo "Welcome to the Nostr Twenty Nine Setup!"
    echo
}

# Function to check if script is run as root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
    else
        echo "Cannot detect OS" 1>&2
        exit 1
    fi
}

install_docker() {
    case $OS in
        "Ubuntu" | "Debian GNU/Linux")
            apt-get update
            apt-get install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        "Fedora" | "Red Hat Enterprise Linux" | "CentOS Linux")
            dnf -y install dnf-plugins-core
            dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        *)
            echo "Unsupported OS: $OS" 1>&2
            exit 1
            ;;
    esac
    systemctl enable docker
    systemctl start docker
    echo "Docker and Docker Compose installed successfully"
}

install_caddy() {
    case $OS in
        "Ubuntu" | "Debian GNU/Linux")
            apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
            apt-get update
            apt-get install -y caddy
            ;;
        "Fedora" | "Red Hat Enterprise Linux" | "CentOS Linux")
            dnf install -y 'dnf-command(copr)'
            dnf copr enable -y @caddy/caddy
            dnf install -y caddy
            ;;
        *)
            echo "Unsupported OS: $OS" 1>&2
            exit 1
            ;;
    esac
    echo "Caddy installed successfully"
}

get_docker_compose_cmd() {
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "Docker Compose not found. Please install Docker Compose and try again." >&2
        exit 1
    fi
}

get_ip() {
    # Try to get the IP using ip command
    if command -v ip >/dev/null 2>&1; then
        IP=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n 1)
    # If ip command fails, try ifconfig
    elif command -v ifconfig >/dev/null 2>&1; then
        IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1' | head -n 1)
    # If both fail, use a more universal method with hostname
    else
        IP=$(hostname -I | awk '{print $1}')
    fi

    # If we still don't have an IP, try to get it from an external service
    if [ -z "$IP" ]; then
        IP=$(curl -s https://api.ipify.org)
    fi

    # Output the IP
    if [ -n "$IP" ]; then
        echo "$IP"
    else
        echo "Unable to determine IP address"
        return 1
    fi
}

get_domain_input() {
    while true; do
        read -p "Enter your domain name (e.g., example.com) or press Enter to use public ip: " domain
        if [ -z "$domain" ]; then
            break
        else
            read -p "Is this correct? (y/n): " confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                break
            fi
        fi
    done
    echo $domain
}

setup_vapor_app() {
    local domain=$1
    local docker_compose_cmd=$(get_docker_compose_cmd)

    git clone https://github.com/Galaxoid-Labs/NostrTwentyNine.git
    cd NostrTwentyNine
    $docker_compose_cmd up -d
    echo "Nostr Twenty Nine is now running with Docker Compose"

    # Configure Caddy
    echo "Configuring Caddy..."
    cat > /etc/caddy/Caddyfile <<EOL
$domain

reverse_proxy :8080
EOL

    echo "Reloading Caddy..."
    if ! systemctl reload caddy; then
        echo "Failed to reload Caddy. Checking Caddy status..."
        systemctl status caddy.service
        echo "Checking Caddy logs..."
        journalctl -xeu caddy.service
        echo "Please check the Caddy configuration and try to reload it manually."
        echo "You can edit the Caddyfile at /etc/caddy/Caddyfile"
    else
        echo "Caddy configured and reloaded successfully."
    fi
}

display_commands() {
    local docker_compose_cmd=$(get_docker_compose_cmd)
    echo "To stop Nostr Twenty Nine, run:"
    echo "cd /root/NostrTwentyNine && $docker_compose_cmd down"
    echo
    echo "To start Nostr Twenty Nine, run:"
    echo "cd /root/NostrTwentyNine && $docker_compose_cmd up -d"
    echo
    echo "To view logs, run:"
    echo "cd /root/NostrTwentyNine && $docker_compose_cmd logs -f"
}

ip=$(get_ip)

display_header
check_root
detect_os
install_docker
install_caddy

domain=$(get_domain_input)

setup_vapor_app

if [ -z "$domain" ]; then
    echo "Setup complete. Your Nostr Twenty Nine should now be accessible at http://$ip"
    echo "Once you get a domain and you've pointed it to this machine you can edit /etc/caddy/Caddyfile"
    echo "and replace :80 with your domain name"
    echo "This should automatically setup your relay with ssl connection"
else
    echo "Setup complete. Your Nostr Twenty Nine should now be accessible at https://$domain"
fi
echo
echo "Here are some useful commands to manage your Nostr Twenty Nine instance:"
display_commands
