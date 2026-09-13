#!/usr/bin/env bash

# ============================================
# NextCloud on Proxmox - Deployment Script
# ============================================
#
# This script provides an intelligent wrapper around the Ansible playbooks
# for deploying NextCloud and Collabora Office on Proxmox.
#
# It handles:
# - Checking prerequisites
# - Verifying the shared Proxmox credential (../Shared/Ansible/)
# - Running the deployment
# - Providing helpful error messages
#
# Usage:
#   ./deploy.sh
#
# The script will guide you through the process interactively.
#
# ============================================

set -e  # Exit on any error
set -u  # Exit on undefined variable

# ============================================
# Color Definitions for Pretty Output
# ============================================

# ANSI color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================
# Helper Functions
# ============================================

# Print functions with color formatting
print_header() {
    echo -e "${CYAN}============================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================${NC}"
    echo ""
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# ============================================
# Prerequisite Checks
# ============================================

check_prerequisites() {
    # Check if all required tools are installed
    # Returns 0 if all checks pass, 1 otherwise
    
    print_header "Checking Prerequisites"
    
    local all_ok=0
    
    # Check for Ansible
    if ! command -v ansible-playbook &> /dev/null; then
        print_error "Ansible is not installed"
        echo "  Install it with: sudo apt install ansible  (Debian/Ubuntu)"
        echo "              or: brew install ansible      (macOS)"
        echo "              or: pip install ansible       (pip)"
        all_ok=1
    else
        local ansible_version=$(ansible-playbook --version | head -n1)
        print_success "Ansible found: $ansible_version"
    fi
    
    # Check for SSH
    if ! command -v ssh &> /dev/null; then
        print_error "SSH client is not installed"
        echo "  Install it with: sudo apt install openssh-client"
        all_ok=1
    else
        print_success "SSH client found"
    fi
    
    # Check for Python proxmoxer library
    if ! python3 -c "import proxmoxer" &> /dev/null; then
        print_error "Python proxmoxer library is not installed"
        echo "  This is required for Proxmox API communication"
        echo "  Install it with: pip3 install proxmoxer requests --user"
        echo "              or: sudo apt install python3-proxmoxer python3-requests  (Debian/Ubuntu)"
        all_ok=1
    else
        print_success "Python proxmoxer library found"
    fi
    
    # Check for Python requests library
    if ! python3 -c "import requests" &> /dev/null; then
        print_error "Python requests library is not installed"
        echo "  This is required for Proxmox API communication"
        echo "  Install it with: pip3 install requests --user"
        echo "              or: sudo apt install python3-requests  (Debian/Ubuntu)"
        all_ok=1
    else
        print_success "Python requests library found"
    fi
    
    # Check for required Ansible collections
    if ! ansible-galaxy collection list | grep -q "community.general"; then
        print_warning "Ansible community.general collection not found"
        echo "  Installing it now..."
        if ansible-galaxy collection install -r requirements.yaml; then
            print_success "community.general collection installed"
        else
            print_error "Failed to install community.general collection"
            all_ok=1
        fi
    else
        print_success "Ansible community.general collection found"
    fi
    
    # Check for community.proxmox collection
    if ! ansible-galaxy collection list | grep -q "community.proxmox"; then
        print_warning "Ansible community.proxmox collection not found"
        echo "  Installing it now..."
        if ansible-galaxy collection install community.proxmox; then
            print_success "community.proxmox collection installed"
        else
            print_error "Failed to install community.proxmox collection"
            all_ok=1
        fi
    else
        print_success "Ansible community.proxmox collection found"
    fi
    
    echo ""
    return $all_ok
}

# ============================================
# SSH Key Management
# ============================================

setup_ssh_keys() {
    # Generate SSH keys if they don't exist
    # These keys are used to access the containers after creation
    
    print_header "SSH Key Setup"
    
    local ssh_dir="./ssh_keys"
    local private_key="$ssh_dir/id_ed25519"
    local public_key="$ssh_dir/id_ed25519.pub"
    
    # Check if keys already exist
    if [[ -f "$private_key" ]] && [[ -f "$public_key" ]]; then
        print_success "SSH keys already exist"
        echo "  Private key: $private_key"
        echo "  Public key: $public_key"
        echo ""
        return 0
    fi
    
    # Create directory if it doesn't exist
    if [[ ! -d "$ssh_dir" ]]; then
        print_info "Creating SSH keys directory..."
        mkdir -p "$ssh_dir"
    fi
    
    # Generate new SSH key pair
    print_info "Generating new SSH key pair for container access..."
    echo "  This key will be used to SSH into the NextCloud and Collabora containers"
    echo ""
    
    if ssh-keygen -t ed25519 -f "$private_key" -N "" -C "nextcloud-deployment-key"; then
        # Set restrictive permissions on private key
        chmod 600 "$private_key"
        chmod 644 "$public_key"
        
        print_success "SSH keys generated successfully"
        echo "  Private key: $private_key (permissions: 600)"
        echo "  Public key: $public_key (permissions: 644)"
        echo ""
    else
        print_error "Failed to generate SSH keys"
        return 1
    fi
}

# ============================================
# Shared Proxmox credential check
# ============================================

check_shared_credential() {
    # This project uses the shared svc_ansible@pve credential, provisioned
    # once per cluster by ../Shared/Ansible/create-pve_svc_user.yaml. It
    # is NOT created here.

    print_header "Shared Proxmox Credential"

    local shared_vault="../Shared/Ansible/group_vars/proxmox_cluster/vault.yaml"
    if [[ -f "$shared_vault" ]]; then
        print_success "Found shared credential ($shared_vault)"
        echo ""
        return 0
    fi

    print_error "Shared Proxmox credential not found."
    echo "  Provision it once per cluster:"
    echo "    cd ../Shared/Ansible && ansible-playbook create-pve_svc_user.yaml"
    echo "  See ../Shared/Ansible/README.md."
    echo ""
    return 1
}

# ============================================
# Deployment
# ============================================

run_deployment() {
    # Run the main NextCloud deployment playbook
    
    print_header "NextCloud Deployment"
    
    print_info "Starting deployment playbook..."
    echo "  This will create and configure NextCloud and Collabora containers"
    echo "  Estimated time: 10-15 minutes depending on your connection"
    echo ""
    
    # Check if config.yaml exists and use it
    local extra_vars=""
    if [ -f "config.yaml" ]; then
        print_success "Using config.yaml for deployment variables"
        extra_vars="-e @config.yaml"
    else
        print_info "No config.yaml found - will use interactive prompts"
    fi
    
    # Run the deployment playbook with optional config file
    if ansible-playbook deploy_nextcloud.yaml $extra_vars; then
        print_success "Deployment completed successfully!"
        echo ""
        return 0
    else
        print_error "Deployment failed"
        echo "  Please check the error messages above"
        echo ""
        return 1
    fi
}

# ============================================
# Main Execution Flow
# ============================================

main() {
    # Main script execution
    # Orchestrates the entire deployment process
    
    clear
    print_header "NextCloud on Proxmox - Automated Deployment"
    
    echo "This script will help you deploy NextCloud and Collabora Office"
    echo "on your Proxmox server."
    echo ""
    
    # ========================================
    # Check for Configuration File
    # ========================================
    
    if [ -f "config.yaml" ]; then
        print_success "Configuration file found: config.yaml"
        echo "  Using pre-configured values from config.yaml"
        echo "  You will NOT be prompted for already-configured values"
        echo ""
        echo "  To use interactive prompts instead:"
        echo "    mv config.yaml config.yaml.backup"
        echo ""
    else
        print_info "No config.yaml found - will use interactive prompts"
        echo "  You will be prompted for all configuration values"
        echo ""
        echo "  To skip prompts in future deployments:"
        echo "    cp config.yaml.example config.yaml"
        echo "    vim config.yaml  # Edit with your values"
        echo ""
    fi
    
    echo "The process includes:"
    echo "  1. Checking prerequisites (Ansible, SSH, etc.)"
    echo "  2. Setting up SSH keys for container access"
    echo "  3. Verifying the shared Proxmox credential is present"
    echo "  4. Deploying NextCloud and Collabora containers"
    echo ""
    
    read -p "Press Enter to continue or Ctrl+C to cancel..."
    echo ""
    
    # Step 1: Check prerequisites
    if ! check_prerequisites; then
        print_error "Prerequisites check failed"
        echo "  Please install the missing requirements and try again"
        exit 1
    fi
    
    # Step 2: Setup SSH keys
    if ! setup_ssh_keys; then
        print_error "SSH key setup failed"
        exit 1
    fi
    
    # Step 3: Verify the shared Proxmox credential
    if ! check_shared_credential; then
        print_error "Shared Proxmox credential missing"
        exit 1
    fi

    # Step 4: Run deployment
    if ! run_deployment; then
        print_error "Deployment failed"
        exit 1
    fi

    # Final success message
    print_header "Deployment Complete!"
    
    echo "Your NextCloud instance is now ready to use!"
    echo ""
    echo "Check the output above for:"
    echo "  - NextCloud URL and admin credentials"
    echo "  - Collabora URL"
    echo "  - Next steps for configuration"
    echo ""
    print_success "Thank you for using this deployment script!"
}

# ============================================
# Script Entry Point
# ============================================

# Run main function
main "$@"

# ============================================
# End of Script
# ============================================
