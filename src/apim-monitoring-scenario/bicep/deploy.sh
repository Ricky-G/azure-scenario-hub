#!/bin/bash

###############################################################################
# Deploy Azure API Management Monitoring Scenario
###############################################################################
# This script deploys the APIM monitoring scenario including:
# - Resource Group
# - API Management Developer SKU
# - 6 Sample APIs with policies
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Functions
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

usage() {
    cat << EOF
Usage: $0 <location> <apim-service-name> [options]

Deploy Azure API Management Monitoring Scenario

Arguments:
    location            Azure region for deployment (e.g., eastus)
    apim-service-name   Name for the API Management service (must be globally unique)

Options:
    --publisher-email   Email address for the API publisher (default: admin@example.com)
    --publisher-name    Organization name (default: Contoso)
    --enable-appinsights Enable Application Insights integration
    --skip-confirmation Skip deployment confirmation prompt
    -h, --help          Show this help message

Examples:
    $0 eastus apim-demo-unique123
    $0 westus my-apim-001 --publisher-email admin@contoso.com --enable-appinsights
EOF
    exit 1
}

# Parse arguments
if [ $# -lt 2 ]; then
    usage
fi

LOCATION="$1"
APIM_SERVICE_NAME="$2"
shift 2

# Default values
PUBLISHER_EMAIL="admin@example.com"
PUBLISHER_NAME="Contoso"
ENABLE_APP_INSIGHTS="false"
SKIP_CONFIRMATION=false

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --publisher-email)
            PUBLISHER_EMAIL="$2"
            shift 2
            ;;
        --publisher-name)
            PUBLISHER_NAME="$2"
            shift 2
            ;;
        --enable-appinsights)
            ENABLE_APP_INSIGHTS="true"
            shift
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

# Main deployment
main() {
    print_header "Azure APIM Monitoring Scenario Deployment"

    # Display configuration
    print_info "Deployment Configuration:"
    print_detail "  Location:            $LOCATION"
    print_detail "  APIM Service Name:   $APIM_SERVICE_NAME"
    print_detail "  Publisher Email:     $PUBLISHER_EMAIL"
    print_detail "  Publisher Name:      $PUBLISHER_NAME"
    print_detail "  App Insights:        $ENABLE_APP_INSIGHTS"

    # Check Azure CLI installation
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed. Please install it first."
        exit 1
    fi

    # Check if logged in to Azure
    print_info "\nChecking Azure login status..."
    if ! az account show &> /dev/null; then
        print_info "Not logged in to Azure. Please login..."
        az login
    fi
    
    ACCOUNT_NAME=$(az account show --query name -o tsv)
    USER_NAME=$(az account show --query user.name -o tsv)
    print_success "Logged in as: $USER_NAME"
    print_success "Subscription: $ACCOUNT_NAME"

    # Confirm deployment
    if [ "$SKIP_CONFIRMATION" = false ]; then
        print_info "\nDeployment will take approximately 15-20 minutes."
        read -p "Continue with deployment? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Deployment cancelled by user."
            exit 0
        fi
    fi

    # Start deployment
    print_header "Starting Bicep Deployment"
    
    DEPLOYMENT_NAME="apim-monitoring-$(date +%Y%m%d-%H%M%S)"
    
    print_detail "Deployment name: $DEPLOYMENT_NAME"
    print_info "\nDeploying infrastructure... This will take 15-20 minutes."
    print_info "☕ This is a good time for a coffee break!\n"

    # Execute deployment
    if ! DEPLOYMENT_OUTPUT=$(az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location "$LOCATION" \
        --template-file "main.bicep" \
        --parameters \
            location="$LOCATION" \
            apimServiceName="$APIM_SERVICE_NAME" \
            publisherEmail="$PUBLISHER_EMAIL" \
            publisherName="$PUBLISHER_NAME" \
            enableApplicationInsights="$ENABLE_APP_INSIGHTS" \
        --output json 2>&1); then
        print_error "Deployment failed!"
        echo "$DEPLOYMENT_OUTPUT"
        exit 1
    fi

    print_success "\nDeployment completed successfully!"

    # Parse outputs
    RESOURCE_GROUP=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.resourceGroupName.value')
    GATEWAY_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.apimGatewayUrl.value')
    PORTAL_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.apimPortalUrl.value')
    DEV_PORTAL_URL=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.apimDeveloperPortalUrl.value')

    # Display outputs
    print_header "Deployment Outputs"
    print_detail "Resource Group:        $RESOURCE_GROUP"
    print_detail "APIM Service Name:     $APIM_SERVICE_NAME"
    echo -e "${CYAN}Gateway URL:           $GATEWAY_URL${NC}"
    echo -e "${CYAN}Azure Portal:          $PORTAL_URL${NC}"
    echo -e "${CYAN}Developer Portal:      $DEV_PORTAL_URL${NC}"
    
    WORKBOOK_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.workbookDisplayName.value')
    echo -e "${GREEN}Monitoring Workbook:   $WORKBOOK_NAME${NC}"

    if [ "$ENABLE_APP_INSIGHTS" = "true" ]; then
        APP_INSIGHTS_NAME=$(echo "$DEPLOYMENT_OUTPUT" | jq -r '.properties.outputs.appInsightsName.value')
        print_detail "App Insights:          $APP_INSIGHTS_NAME"
    fi

    # Display sample APIs
    print_header "Sample APIs Deployed"
    print_detail "1. Weather API:            $GATEWAY_URL/weather/{city}"
    print_detail "2. Product Search:         $GATEWAY_URL/products/search"
    print_detail "3. User Validation:        $GATEWAY_URL/users/validate"
    print_detail "4. Currency Conversion:    $GATEWAY_URL/currency/convert"
    print_detail "5. Health Monitor:         $GATEWAY_URL/health/status"
    print_detail "6. Delay Simulator:        $GATEWAY_URL/simulate/delay"

    # Get subscription key
    print_info "\nRetrieving subscription key..."
    if SUBSCRIPTIONS=$(az apim product subscription list \
        --resource-group "$RESOURCE_GROUP" \
        --service-name "$APIM_SERVICE_NAME" \
        --product-id "unlimited" \
        --output json 2>/dev/null); then
        
        if [ "$(echo "$SUBSCRIPTIONS" | jq '. | length')" -gt 0 ]; then
            SUBSCRIPTION_ID=$(echo "$SUBSCRIPTIONS" | jq -r '.[0].name')
            KEYS=$(az apim product subscription show \
                --resource-group "$RESOURCE_GROUP" \
                --service-name "$APIM_SERVICE_NAME" \
                --product-id "unlimited" \
                --subscription-id "$SUBSCRIPTION_ID" \
                --output json)
            
            PRIMARY_KEY=$(echo "$KEYS" | jq -r '.primaryKey')
            
            if [ -n "$PRIMARY_KEY" ] && [ "$PRIMARY_KEY" != "null" ]; then
                print_header "Quick Test"
                print_info "Use this subscription key for testing:"
                echo -e "${CYAN}$PRIMARY_KEY${NC}"
                
                print_info "\nTest command example:"
                print_detail "curl \"$GATEWAY_URL/health/status\" -H \"Ocp-Apim-Subscription-Key: $PRIMARY_KEY\""
            fi
        fi
    else
        print_info "Note: Get subscription key from Azure Portal"
    fi

    # Next steps
    print_header "Next Steps"
    echo -e "${CYAN}1. 📊 View the monitoring dashboard:${NC}"
    print_detail "   - Go to Azure Portal > APIM > Workbooks"
    print_detail "   - Open: $WORKBOOK_NAME"
    echo ""
    print_detail "2. Visit the Developer Portal to create subscriptions: $DEV_PORTAL_URL"
    print_detail "3. Test the APIs using the examples in README.md"
    print_detail "4. Monitor API metrics in the Workbook dashboard"
    print_detail "5. Explore API policies in the Azure Portal"

    print_success "\nDeployment complete!\n"
}

# Run main function
main
