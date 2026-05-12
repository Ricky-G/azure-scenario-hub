#!/bin/bash

###############################################################################
# Cleanup Azure API Management Monitoring Scenario
###############################################################################
# This script removes all resources created by the APIM monitoring scenario.
###############################################################################

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m'

print_header() {
    echo -e "\n${CYAN}========================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}$1${NC}"
}

print_detail() {
    echo -e "${GRAY}$1${NC}"
}

print_warning() {
    echo -e "${RED}$1${NC}"
}

usage() {
    cat << EOF
Usage: $0 [options]

Cleanup Azure API Management Monitoring Scenario

Options:
    --resource-group    Name of the resource group to delete (default: rg-apim-monitoring)
    --skip-confirmation Skip deletion confirmation prompt
    -h, --help          Show this help message

Examples:
    $0
    $0 --resource-group rg-apim-monitoring --skip-confirmation
EOF
    exit 1
}

# Default values
RESOURCE_GROUP_NAME="rg-apim-monitoring"
SKIP_CONFIRMATION=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resource-group)
            RESOURCE_GROUP_NAME="$2"
            shift 2
            ;;
        --skip-confirmation)
            SKIP_CONFIRMATION=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

main() {
    print_header "Azure APIM Monitoring Scenario Cleanup"

    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed."
        exit 1
    fi

    # Check if logged in
    print_info "Checking Azure login status..."
    if ! az account show &> /dev/null; then
        print_info "Not logged in to Azure. Please login..."
        az login
    fi
    
    ACCOUNT_NAME=$(az account show --query name -o tsv)
    USER_NAME=$(az account show --query user.name -o tsv)
    print_success "Logged in as: $USER_NAME"
    print_success "Subscription: $ACCOUNT_NAME"

    # Check if resource group exists
    print_info "\nChecking if resource group exists..."
    if [ "$(az group exists --name "$RESOURCE_GROUP_NAME")" = "false" ]; then
        print_info "Resource group '$RESOURCE_GROUP_NAME' does not exist."
        print_success "Nothing to cleanup."
        exit 0
    fi

    print_success "Resource group found: $RESOURCE_GROUP_NAME"

    # Get resources
    print_info "\nFetching resources..."
    RESOURCES=$(az resource list --resource-group "$RESOURCE_GROUP_NAME" --output json)
    RESOURCE_COUNT=$(echo "$RESOURCES" | jq '. | length')

    if [ "$RESOURCE_COUNT" -eq 0 ]; then
        print_info "No resources found in the resource group."
    else
        print_info "\nResources to be deleted:"
        echo "$RESOURCES" | jq -r '.[] | "  - \(.name) (\(.type))"' | while read -r line; do
            print_detail "$line"
        done
    fi

    # Confirm deletion
    if [ "$SKIP_CONFIRMATION" = false ]; then
        print_warning "\n⚠️  WARNING: This will permanently delete all resources in the resource group."
        print_warning "Resource Group: $RESOURCE_GROUP_NAME"
        read -p $'\nAre you sure you want to continue? (yes/N): ' -r
        if [[ ! $REPLY == "yes" ]]; then
            print_info "Cleanup cancelled by user."
            exit 0
        fi
    fi

    # Delete resource group
    print_header "Deleting Resource Group"
    print_info "Deleting resource group: $RESOURCE_GROUP_NAME"
    print_detail "This may take a few minutes...\n"

    az group delete --name "$RESOURCE_GROUP_NAME" --yes --no-wait

    print_success "Deletion initiated successfully!"
    print_detail "\nNote: Deletion is running in the background."
    print_detail "You can check status with:"
    echo -e "${CYAN}  az group show --name $RESOURCE_GROUP_NAME${NC}"
    
    print_success "\nCleanup complete!\n"
}

main
