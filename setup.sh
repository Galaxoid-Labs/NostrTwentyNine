#!/bin/bash

set -e

# Check if the script is being run with a TTY
if [ -t 0 ]; then
    # If it is, we're good to go
    interactive=true
else
    # If not, we need to re-run the script in a way that allocates a TTY
    if [ -z "$NOSTR_SETUP_RUNNING" ]; then
        export NOSTR_SETUP_RUNNING=1
        exec <&- && exec <>/dev/tty && exec "$0" "$@"
        exit
    fi
fi

# Function to display ASCII header
display_header() {
    cat << "EOF"
     __          _       _____                     _             __ _
  /\ \ \___  ___| |_ _ _/__   \__      _____ _ __ | |_ _   _  /\ \ (_)_ __   ___
 /  \/ / _ \/ __| __| '__|/ /\/\ \ /\ / / _ \ '_ \| __| | | |/  \/ / | '_ \ / _ \
/ /\  / (_) \__ \ |_| |  / /    \ V  V /  __/ | | | |_| |_| / /\  /| | | | |  __/
\_\ \/ \___/|___/\__|_|  \/      \_/\_/ \___|_| |_|\__|\__, \_\ \/ |_|_| |_|\___|
                                                       |___/
EOF
    echo
    echo "Welcome to the Nostr Twenty Nine Setup!"
    echo
}

# Function to get public IP
get_public_ip() {
    curl -s https://api.ipify.org
}

# Function to get domain input
get_domain_input() {
    local public_ip=$(get_public_ip)
    echo "Please enter your domain information:"
    echo "Enter your domain name (or press enter to use public IP: $public_ip): "
    read domain
    if [ -z "$domain" ]; then
        domain=$public_ip
        echo "Using public IP: $domain"
    else
        echo "Using domain: $domain"
    fi
    echo $domain
}

# Function to check if script is run as root
check_root() {
    echo "Checking if script is run as root..."
    if [ "$(id -u)" != "0" ]; then
        echo "This script must be run as root" 1>&2
        exit 1
    fi
    echo "Script is running as root."
}

# Function to detect OS
detect_os() {
    echo "Detecting operating system..."
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        echo "Detected OS: $OS"
    else
        echo "Cannot detect OS" 1>&2
        exit 1
    fi
}

# Function to install Docker and Docker Compose
install_docker() {
    echo "Installing Docker and Docker Compose..."
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

# Function to install Caddy
install_caddy() {
    echo "Installing Caddy..."
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

# Function to determine Docker Compose command
get_docker_compose_cmd() {
    echo "Determining Docker Compose command..."
    if command -v docker-compose &> /dev/null; then
        echo "docker-compose"
    elif docker compose version &> /dev/null; then
        echo "docker compose"
    else
        echo "Docker Compose not found. Please install Docker Compose and try again." >&2
        exit 1
    fi
}

# Function to setup Vapor app and configure Caddy
setup_vapor_app() {
    local domain=$1
    echo "Setting up Vapor app for domain: $domain"
    local docker_compose_cmd=$(get_docker_compose_cmd)
    
    echo "Cloning NostrTwentyNine repository..."
    git clone https://github.com/Galaxoid-Labs/NostrTwentyNine.git
    cd NostrTwentyNine
    echo "Starting Docker containers..."
    $docker_compose_cmd up -d
    echo "Nostr Twenty Nine is now running with Docker Compose"

    # Configure Caddy
    echo "Configuring Caddy..."
    cat > /etc/caddy/Caddyfile <<EOL
$domain {
    reverse_proxy localhost:8080
}
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

# Function to display stop/start commands
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

# Main execution
display_header

echo "Beginning domain input process..."
domain=$(get_domain_input)

check_root
detect_os
install_docker
install_caddy

echo "Setting up Vapor app..."
setup_vapor_app "$domain"

echo "Setup complete. Your Nostr Twenty Nine should now be accessible at https://$domain"
echo "If you encountered any issues with Caddy, please check the output above for troubleshooting information."
echo
echo "Here are some useful commands to manage your Nostr Twenty Nine instance:"
display_commands
