#!/usr/bin/perl

use strict;
use warnings;

# Function to find the full path of a command
sub which {
    my ($cmd) = @_;
    my $path = `which $cmd 2>/dev/null`;
    chomp $path;
    return $path if $path;
    die "Cannot find $cmd in PATH\n";
}

# Function to run system commands with error checking
sub run_command {
    my ($command) = @_;
    print "Executing: $command\n";  # Debug output
    system($command);
    if ($? == -1) {
        die "Failed to execute: $command\n";
    } elsif ($? & 127) {
        die sprintf("Child died with signal %d, %s coredump\n",
            ($? & 127),  ($? & 128) ? 'with' : 'without');
    } elsif ($? != 0) {
        die sprintf("Command failed: $command (exit code: %d)\n", $? >> 8);
    }
}

# Function to cleanup previous installation
sub cleanup {
    print "Cleaning up previous installation...\n";
    
    # Remove NostrTwentyNine directory
    if (-d "NostrTwentyNine") {
        run_command(which('rm') . " -rf NostrTwentyNine");
    }
    
    # Remove Caddy configuration
    if (-f "/etc/caddy/Caddyfile") {
        run_command(which('rm') . " -f /etc/caddy/Caddyfile");
    }
    
    # Docker cleanup
    if (system("which docker > /dev/null 2>&1") == 0) {
        # Stop all running containers
        run_command(which('docker') . " stop \$(docker ps -aq)") if system("docker ps -q") == 0;
        
        # Remove all containers
        run_command(which('docker') . " rm \$(docker ps -aq)") if system("docker ps -aq") == 0;
        
        # Remove all images
        run_command(which('docker') . " rmi \$(docker images -q)") if system("docker images -q") == 0;
        
        # Remove all volumes
        run_command(which('docker') . " volume prune -f");
        
        # Remove all networks
        run_command(which('docker') . " network prune -f");
        
        # Remove all build cache
        run_command(which('docker') . " builder prune -af");
    }
    
    print "Cleanup complete.\n";
}

# Check if running as root
if ($> != 0) {
    print "This script must be run as root. Please use sudo.\n";
    exit 1;
}

# Function to detect OS
sub detect_os {
    if (-f "/etc/os-release") {
        my $os = `grep -E '^NAME=' /etc/os-release | cut -d'"' -f2`;
        chomp $os;
        return $os;
    } else {
        die "Cannot detect OS\n";
    }
}

# Function to check and install Term::ANSIColor
sub ensure_term_ansicolor {
    eval {
        require Term::ANSIColor;
        Term::ANSIColor->import();
    };
    if ($@) {
        print "Term::ANSIColor is not installed. Attempting to install...\n";
        my $os = detect_os();
        if ($os =~ /Ubuntu|Debian/) {
            run_command(which('apt-get') . " update");
            run_command(which('apt-get') . " install -y libterm-ansicolor-perl");
        } elsif ($os =~ /Fedora|Red Hat|CentOS/) {
            run_command(which('dnf') . " install -y perl-Term-ANSIColor");
        } else {
            print "Unable to automatically install Term::ANSIColor on this OS.\n";
            print "You can try installing it manually with: cpan Term::ANSIColor\n";
            return;
        }
        
        # Check again if it's installed
        eval {
            require Term::ANSIColor;
            Term::ANSIColor->import();
        };
        if ($@) {
            print "Failed to install Term::ANSIColor. Continuing without color support.\n";
        } else {
            print "Term::ANSIColor installed successfully.\n";
        }
    }
}

ensure_term_ansicolor();

use Term::ANSIColor;

# Function to display ASCII header
sub display_header {
    print colored(<<'EOF', 'bold blue');
     __          _       _____                     _             __ _
  /\ \ \___  ___| |_ _ _/__   \__      _____ _ __ | |_ _   _  /\ \ (_)_ __   ___
 /  \/ / _ \/ __| __| '__|/ /\/\ \ /\ / / _ \ '_ \| __| | | |/  \/ / | '_ \ / _ \
/ /\  / (_) \__ \ |_| |  / /    \ V  V /  __/ | | | |_| |_| / /\  /| | | | |  __/
\_\ \/ \___/|___/\__|_|  \/      \_/\_/ \___|_| |_|\__|\__, \_\ \/ |_|_| |_|\___|
                                                       |___/
EOF
    print "\nWelcome to the Nostr Twenty Nine Setup!\n\n";
}

# Function to install Docker and Docker Compose
sub install_docker {
    my $os = shift;
    print "Installing Docker and Docker Compose...\n";
    if ($os =~ /Ubuntu|Debian/) {
        run_command(which('apt-get') . " update");
        run_command(which('apt-get') . " install -y apt-transport-https ca-certificates curl software-properties-common");
        run_command(which('curl') . " -fsSL https://download.docker.com/linux/ubuntu/gpg | " . which('gpg') . " --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg");
        run_command("echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | " . which('tee') . " /etc/apt/sources.list.d/docker.list > /dev/null");
        run_command(which('apt-get') . " update");
        run_command(which('apt-get') . " install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin");
    } elsif ($os =~ /Fedora|Red Hat|CentOS/) {
        run_command(which('dnf') . " -y install dnf-plugins-core");
        run_command(which('dnf') . " config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo");
        run_command(which('dnf') . " install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin");
    } else {
        die "Unsupported OS: $os\n";
    }
    run_command(which('systemctl') . " enable docker");
    run_command(which('systemctl') . " start docker");
    print "Docker and Docker Compose installed successfully\n";
}

# Function to install Caddy
sub install_caddy {
    my $os = shift;
    print "Installing Caddy...\n";
    if ($os =~ /Ubuntu|Debian/) {
        run_command(which('apt-get') . " install -y debian-keyring debian-archive-keyring apt-transport-https");
        run_command(which('curl') . " -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | " . which('gpg') . " --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg");
        run_command(which('curl') . " -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | " . which('tee') . " /etc/apt/sources.list.d/caddy-stable.list");
        run_command(which('apt-get') . " update");
        run_command(which('apt-get') . " install -y caddy");
    } elsif ($os =~ /Fedora|Red Hat|CentOS/) {
        run_command(which('dnf') . " install -y 'dnf-command(copr)'");
        run_command(which('dnf') . " copr enable -y \@caddy/caddy");
        run_command(which('dnf') . " install -y caddy");
    } else {
        die "Unsupported OS: $os\n";
    }
    print "Caddy installed successfully\n";
}

# Function to get public IP
sub get_public_ip {
    my $ip = `curl -s https://api.ipify.org`;
    chomp $ip;
    return $ip;
}

# Function to get domain input
sub get_domain_input {
    my $public_ip = get_public_ip();
    print "Enter your domain name (or press enter to use public IP: $public_ip): ";
    my $domain = <STDIN>;
    chomp $domain;
    $domain = '' if $domain eq $public_ip;
    print "Using " . ($domain ? "domain: $domain" : "public IP") . "\n";
    return $domain;
}

# Function to setup Vapor app and configure Caddy
sub setup_vapor_app {
    my $domain = shift;
    my $docker_compose_cmd = get_docker_compose_cmd();
    
    print "Setting up Nostr Twenty Nine...\n";
    run_command(which('git') . " clone https://github.com/Galaxoid-Labs/NostrTwentyNine.git");
    chdir("NostrTwentyNine") or die "Can't chdir to NostrTwentyNine: $!";
    run_command("$docker_compose_cmd up -d");

    # Configure Caddy
    open my $fh, '>', '/etc/caddy/Caddyfile' or die "Could not open file '/etc/caddy/Caddyfile' $!";
    if ($domain) {
        print $fh "$domain\n\nreverse_proxy :8080\n";
    } else {
        print $fh ":80\n\nreverse_proxy :8080\n";
    }
    close $fh;
    
    run_command(which('systemctl') . " reload caddy");
    print "Nostr Twenty Nine setup complete\n";
}

# Function to determine Docker Compose command
sub get_docker_compose_cmd {
    return "docker-compose" if system("command -v docker-compose > /dev/null 2>&1") == 0;
    return "docker compose" if system("docker compose version > /dev/null 2>&1") == 0;
    die "Docker Compose not found. Please install Docker Compose and try again.\n";
}

# Function to check for existing installation
sub check_existing_installation {
    my $existing = 0;
    $existing = 1 if -d "NostrTwentyNine";
    $existing = 1 if -f "/etc/caddy/Caddyfile";
    $existing = 1 if system("docker ps -a | grep -q NostrTwentyNine") == 0;
    return $existing;
}

# Main execution
display_header();

my $os = detect_os();
my $public_ip = get_public_ip();

if (check_existing_installation()) {
    print "Existing installation detected.\n";
    print "Do you want to perform a clean installation? This will remove the existing setup. (y/n): ";
    my $clean_install = <STDIN>;
    chomp $clean_install;
    if (lc($clean_install) eq 'y') {
        print "WARNING: This will remove ALL Docker containers, images, volumes, and networks on this system.\n";
        print "Are you sure you want to proceed? (y/n): ";
        my $confirm = <STDIN>;
        chomp $confirm;
        if (lc($confirm) eq 'y') {
            cleanup();
        } else {
            print "Cleanup cancelled. Proceeding with installation...\n";
        }
    }
} else {
    print "No existing installation detected. Proceeding with fresh installation...\n";
}

my $domain = get_domain_input();

install_docker($os);
install_caddy($os);

setup_vapor_app($domain);

print "\nSetup complete. Your Nostr Twenty Nine should now be accessible at ";
print $domain ? "https://$domain\n" : "http://$public_ip\n";

# Display commands
my $docker_compose_cmd = get_docker_compose_cmd();
print "\nUseful Commands:\n";
print "To stop: cd /root/NostrTwentyNine && $docker_compose_cmd down\n";
print "To start: cd /root/NostrTwentyNine && $docker_compose_cmd up -d\n";
print "To view logs: cd /root/NostrTwentyNine && $docker_compose_cmd logs -f\n";
