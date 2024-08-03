#!/bin/bash

# Colors for formatting
RED='\033[0;31m'    # Red colored text
GREEN='\033[0;32m'  # Green colored text
NC='\033[0m'        # Normal text

# Function to display error message and exit
display_error() {
    echo -e "${RED}Error: $1${NC}" >&2
    exit 1
}

# Function to display success message
display_success() {
    echo -e "${GREEN}$1${NC}"
}

# Remove custom Jenkins image
sudo docker stop my-custom-jenkins || display_error "Failed to remove custom Jenkins image"

# Remove custom Jenkins image
sudo docker image rm my-custom-jenkins || display_error "Failed to remove custom Jenkins image"

# Stop and remove Jenkins container
sudo docker stop jenkins && sudo docker rm jenkins || display_error "Failed to stop and remove Jenkins container"

# Remove Docker volume jenkins_data
sudo docker volume rm jenkins_data || display_error "Failed to remove Docker volume jenkins_data"

# Remove jenkins_data directory
read -p "Enter the absolute path of jenkins_data directory to remove: " jenkins_data_location
sudo rm -rf "$jenkins_data_location" || display_error "Failed to remove jenkins_data directory"

# Remove Dockerfile
rm Dockerfile || display_error "Failed to remove Dockerfile"

display_success "Revert completed successfully"
