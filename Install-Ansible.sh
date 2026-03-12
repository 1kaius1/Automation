#!/usr/bin/env bash
##########
# Install latest version of Ansible using official PPA
##########
set -euo pipefail

echo "Updating package lists..."
sudo apt update

echo "Installing prerequisites..."
sudo apt install -y software-properties-common

echo "Adding official Ansible PPA..."
sudo add-apt-repository -y ppa:ansible/ansible

echo "Updating package lists again..."
sudo apt update

echo "Installing Ansible..."
sudo apt install -y ansible

echo "Installation complete. Version installed:"
ansible --version

