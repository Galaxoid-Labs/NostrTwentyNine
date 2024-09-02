#!/usr/bin/perl

use strict;
use warnings;

# Check if running as root
if ($> != 0) {
    print "This script must be run as root. Please use sudo.\n";
    exit 1;
}

# Function to check and install required modules
sub check_and_install_modules {
    my @required_modules = ('Term::ReadKey', 'Term::ANSIColor');
    my @missing_modules;

    for my $module (@required_modules) {
        eval "require $module";
        if ($@) {
            push @missing_modules, $module;
        }
    }

    if (@missing_modules) {
        print "The following Perl modules are required and will be installed:\n";
        print join(", ", @missing_modules) . "\n";
        print "Installing modules...\n";

        my $os = detect_os();
        if ($os =~ /Ubuntu|Debian/) {
            system("apt-get update");
            system("apt-get install -y libterm-readkey-perl");
        } elsif ($os =~ /Fedora|Red Hat|CentOS/) {
            system("dnf install -y perl-Term-ReadKey");
        } else {
            die "Unsupported OS for automatic module installation\n";
        }

        # Verify installation
        for my $module (@missing_modules) {
            eval "require $module";
            if ($@) {
                die "Failed to install $module. Please install it manually and try again.\n";
            }
        }
        print "Modules installed successfully.\n";
    }
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

# Check and install required modules
check_and_install_modules();

# Now we can safely use these modules
use Term::ReadKey;
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
        system(
            "apt-get update",
            "apt-get install -y apt-transport-https ca-certificates curl software-properties-common",
            "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
            "echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \$(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null",
            "apt-get update",
            "apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
        );
    } elsif ($os =~ /Fedora|Red Hat|CentOS/) {
        system(
            "dnf -y install dnf-plugins-core",
            "dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo",
            "dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
        );
    } else {
        die "Unsupported OS: $os\n";
    }
    system("systemctl enable docker", "systemctl start docker");
    print "Docker and Docker Compose installed successfully\n";
}

# Function to install Caddy
sub install_caddy {
    my $os = shift;
    print "Installing Caddy...\n";
    if ($os =~ /Ubuntu|Debian/) {
        system(
            "apt-get install -y debian-keyring debian-archive-keyring apt-transport-https",
            "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg",
            "curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list",
            "apt-get update",
            "apt-get install -y caddy"
        );
    } elsif ($os =~ /Fedora|Red Hat|CentOS/) {
        system(
            "dnf install -y 'dnf-command(copr)'",
            "dnf copr enable -y \@caddy/caddy",
            "dnf install -y caddy"
        );
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
    system(
        "git clone https://github.com/Galaxoid-Labs/NostrTwentyNine.git",
        "cd NostrTwentyNine",
        "$docker_compose_cmd up -d"
    );

    # Configure Caddy
    open my $fh, '>', '/etc/caddy/Caddyfile' or die "Could not open file '/etc/caddy/Caddyfile' $!";
    if ($domain) {
        print $fh "$domain\n\nreverse_proxy :8080\n";
    } else {
        print $fh ":80\n\nreverse_proxy :8080\n";
    }
    close $fh;
    
    system("systemctl reload caddy");
    print "Nostr Twenty Nine setup complete\n";
}

# Function to determine Docker Compose command
sub get_docker_compose_cmd {
    return "docker-compose" if system("command -v docker-compose > /dev/null 2>&1") == 0;
    return "docker compose" if system("docker compose version > /dev/null 2>&1") == 0;
    die "Docker Compose not found. Please install Docker Compose and try again.\n";
}

# Main execution
display_header();

my $os = detect_os();
my $domain = get_domain_input();

install_docker($os);
install_caddy($os);

setup_vapor_app($domain);

print colored("\nSetup complete. Your Nostr Twenty Nine should now be accessible at ", 'green');
print colored($domain ? "https://$domain\n" : "http://[Your Server IP]\n", 'green bold');

# Display commands
my $docker_compose_cmd = get_docker_compose_cmd();
print colored("\nUseful Commands:\n", 'yellow');
print "To stop: cd /root/NostrTwentyNine && $docker_compose_cmd down\n";
print "To start: cd /root/NostrTwentyNine && $docker_compose_cmd up -d\n";
print "To view logs: cd /root/NostrTwentyNine && $docker_compose_cmd logs -f\n";

print colored("\nPress any key to exit...", 'bold');
ReadMode('cbreak');
ReadKey(0);
ReadMode('normal');
print "\n";
