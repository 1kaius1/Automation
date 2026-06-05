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
# - Optionally creating Proxmox API user
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
# API User Setup
# ============================================

setup_api_user() {
    # Ask user if they need to create an API user
    # If yes, run the setup_proxmox_api.yaml playbook
    
    print_header "Proxmox API User Setup"
    
    # Check if credentials file already exists from previous run
    if [[ -f ".proxmox_credentials.yaml" ]]; then
        print_info "Found existing Proxmox API credentials from previous setup"
        echo ""
        read -p "Do you want to use these credentials? (yes/no) [yes]: " use_existing
        use_existing=${use_existing:-yes}
        
        if [[ "$use_existing" =~ ^[Yy]([Ee][Ss])?$ ]]; then
            print_success "Using existing API credentials"
            echo ""
            return 0
        else
            print_warning "Will create new API credentials (old file will be overwritten)"
            echo ""
        fi
    fi
    
    # Ask if user needs to create API user
    echo "Do you already have Proxmox API credentials?"
    echo "  - If YES: You have a Token ID and Token Secret ready"
    echo "  - If NO: We'll create them for you now"
    echo ""
    read -p "Do you need to create a new Proxmox API user? (yes/no) [no]: " create_user
    create_user=${create_user:-no}
    
    if [[ "$create_user" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        print_info "Running API user creation playbook..."
        echo ""
        
        # Run the API user setup playbook
        if ansible-playbook setup_proxmox_api.yaml; then
            print_success "API user created successfully"
            echo ""
            return 0
        else
            print_error "API user creation failed"
            echo "  Please check the error messages above and try again"
            return 1
        fi
    else
        print_info "Skipping API user creation"
        echo "  You'll be prompted for your existing API credentials during deployment"
        echo ""
        return 0
    fi
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
# Cleanup
# ============================================

offer_cleanup() {
    # Ask user if they want to delete the saved credentials file
    # This is a security best practice
    
    if [[ ! -f ".proxmox_credentials.yaml" ]]; then
        return 0
    fi
    
    echo ""
    print_header "Security Cleanup"
    
    echo "The file '.proxmox_credentials.yaml' contains sensitive API credentials."
    echo "For security, you may want to delete it now that deployment is complete."
    echo ""
    echo "Options:"
    echo "  1. Delete it now (recommended for one-time deployments)"
    echo "  2. Keep it (useful if you plan to run more deployments)"
    echo "  3. Move it to a secure location"
    echo ""
    read -p "What would you like to do? (1/2/3) [1]: " cleanup_choice
    cleanup_choice=${cleanup_choice:-1}
    
    case "$cleanup_choice" in
        1)
            print_info "Securely deleting credentials file..."
            # Use shred if available for secure deletion
            if command -v shred &> /dev/null; then
                shred -u .proxmox_credentials.yaml
                print_success "Credentials file securely deleted"
            else
                rm .proxmox_credentials.yaml
                print_success "Credentials file deleted"
            fi
            ;;
        2)
            print_warning "Keeping credentials file"
            echo "  Remember to protect this file and delete it when no longer needed"
            echo "  Ensure file permissions are restrictive: chmod 600 .proxmox_credentials.yaml"
            chmod 600 .proxmox_credentials.yaml 2>/dev/null || true
            ;;
        3)
            read -p "Enter path to move credentials to: " move_path
            if [[ -n "$move_path" ]]; then
                mv .proxmox_credentials.yaml "$move_path"
                chmod 600 "$move_path" 2>/dev/null || true
                print_success "Credentials moved to: $move_path"
                echo "  File permissions set to 600 (owner read/write only)"
            else
                print_warning "No path provided, keeping file in current location"
            fi
            ;;
        *)
            print_warning "Invalid choice, keeping credentials file"
            ;;
    esac
    echo ""
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
    echo "  3. Optionally creating Proxmox API user"
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
    
    # Step 3: Setup API user (optional)
    if ! setup_api_user; then
        print_error "API user setup failed"
        exit 1
    fi
    
    # Step 4: Run deployment
    if ! run_deployment; then
        print_error "Deployment failed"
        exit 1
    fi
    
    # Step 5: Offer cleanup
    offer_cleanup
    
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
