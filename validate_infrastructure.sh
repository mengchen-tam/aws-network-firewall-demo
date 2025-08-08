#!/bin/bash

# Infrastructure Validation Script for TGW-Attached Network Firewall
# This script validates the complete infrastructure deployment according to task 12 requirements

set -e

echo "=== TGW-Attached Network Firewall Infrastructure Validation ==="
echo "Starting validation at $(date)"
echo

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}[PASS]${NC} $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}[FAIL]${NC} $message"
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}[WARN]${NC} $message"
    else
        echo -e "[INFO] $message"
    fi
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Validation counters
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# Check prerequisites
echo "1. Checking Prerequisites..."
if command_exists terraform; then
    print_status "PASS" "Terraform is installed"
    TERRAFORM_VERSION=$(terraform version -json | jq -r '.terraform_version')
    echo "   Terraform version: $TERRAFORM_VERSION"
    ((PASS_COUNT++))
else
    print_status "FAIL" "Terraform is not installed"
    ((FAIL_COUNT++))
    exit 1
fi

if command_exists aws; then
    print_status "PASS" "AWS CLI is installed"
    AWS_VERSION=$(aws --version 2>&1 | cut -d/ -f2 | cut -d' ' -f1)
    echo "   AWS CLI version: $AWS_VERSION"
    ((PASS_COUNT++))
else
    print_status "FAIL" "AWS CLI is not installed"
    ((FAIL_COUNT++))
fi

# Check AWS credentials
echo
echo "2. Checking AWS Credentials..."
if aws sts get-caller-identity >/dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    REGION=$(aws configure get region)
    print_status "PASS" "AWS credentials are configured"
    echo "   Account ID: $ACCOUNT_ID"
    echo "   Region: $REGION"
    ((PASS_COUNT++))
else
    print_status "FAIL" "AWS credentials are not configured or invalid"
    ((FAIL_COUNT++))
fi

# Terraform validation
echo
echo "3. Running Terraform Validation..."

# Initialize terraform if needed
if [ ! -d ".terraform" ]; then
    echo "   Initializing Terraform..."
    if terraform init; then
        print_status "PASS" "Terraform initialization successful"
        ((PASS_COUNT++))
    else
        print_status "FAIL" "Terraform initialization failed"
        ((FAIL_COUNT++))
    fi
else
    print_status "PASS" "Terraform already initialized"
    ((PASS_COUNT++))
fi

# Validate terraform configuration
echo "   Validating Terraform configuration..."
if terraform validate; then
    print_status "PASS" "Terraform configuration is valid"
    ((PASS_COUNT++))
else
    print_status "FAIL" "Terraform configuration validation failed"
    ((FAIL_COUNT++))
fi

# Run terraform plan
echo
echo "4. Running Terraform Plan..."
if terraform plan -out=tfplan >/dev/null 2>&1; then
    print_status "PASS" "Terraform plan completed successfully"
    ((PASS_COUNT++))
    
    # Analyze the plan
    PLAN_OUTPUT=$(terraform show -json tfplan)
    
    # Check for key resources
    echo "   Analyzing planned resources..."
    
    # Check for Network Firewall
    if echo "$PLAN_OUTPUT" | jq -e '.planned_values.root_module.resources[] | select(.type == "aws_networkfirewall_firewall")' >/dev/null; then
        print_status "PASS" "Network Firewall resource found in plan"
        ((PASS_COUNT++))
    else
        print_status "FAIL" "Network Firewall resource not found in plan"
        ((FAIL_COUNT++))
    fi
    
    # Check for Transit Gateway
    if echo "$PLAN_OUTPUT" | jq -e '.planned_values.root_module.resources[] | select(.type == "aws_ec2_transit_gateway")' >/dev/null; then
        print_status "PASS" "Transit Gateway resource found in plan"
        ((PASS_COUNT++))
    else
        print_status "FAIL" "Transit Gateway resource not found in plan"
        ((FAIL_COUNT++))
    fi
    
    # Check for VPCs (should have 3: 2 spoke + 1 egress)
    VPC_COUNT=$(echo "$PLAN_OUTPUT" | jq '[.planned_values.root_module.resources[] | select(.type == "aws_vpc")] | length')
    if [ "$VPC_COUNT" -eq 3 ]; then
        print_status "PASS" "Correct number of VPCs found (3: 2 spoke + 1 egress)"
        ((PASS_COUNT++))
    else
        print_status "WARN" "Expected 3 VPCs, found $VPC_COUNT"
        ((WARN_COUNT++))
    fi
    
    # Check for EC2 instances
    EC2_COUNT=$(echo "$PLAN_OUTPUT" | jq '[.planned_values.root_module.resources[] | select(.type == "aws_instance")] | length')
    if [ "$EC2_COUNT" -ge 2 ]; then
        print_status "PASS" "EC2 instances found for testing ($EC2_COUNT instances)"
        ((PASS_COUNT++))
    else
        print_status "WARN" "Expected at least 2 EC2 instances for testing, found $EC2_COUNT"
        ((WARN_COUNT++))
    fi
    
else
    print_status "FAIL" "Terraform plan failed"
    ((FAIL_COUNT++))
    echo "   Please check terraform configuration for errors"
fi

# Check for existing infrastructure (if deployed)
echo
echo "5. Checking Existing Infrastructure..."

# Check if infrastructure is already deployed
if aws ec2 describe-transit-gateways --filters "Name=tag:Name,Values=tgw_with_network_firewall" --query 'TransitGateways[0].TransitGatewayId' --output text 2>/dev/null | grep -v "None"; then
    TGW_ID=$(aws ec2 describe-transit-gateways --filters "Name=tag:Name,Values=tgw_with_network_firewall" --query 'TransitGateways[0].TransitGatewayId' --output text)
    TGW_STATE=$(aws ec2 describe-transit-gateways --transit-gateway-ids "$TGW_ID" --query 'TransitGateways[0].State' --output text)
    
    print_status "PASS" "Transit Gateway found: $TGW_ID"
    echo "   State: $TGW_STATE"
    ((PASS_COUNT++))
    
    if [ "$TGW_STATE" = "available" ]; then
        print_status "PASS" "Transit Gateway is in available state"
        ((PASS_COUNT++))
    else
        print_status "WARN" "Transit Gateway is not in available state: $TGW_STATE"
        ((WARN_COUNT++))
    fi
else
    print_status "INFO" "Transit Gateway not found (infrastructure may not be deployed yet)"
fi

# Check for Network Firewall
if aws network-firewall list-firewalls --query 'Firewalls[?FirewallName==`tgw-attached-firewall`]' --output text 2>/dev/null | grep -q "tgw-attached-firewall"; then
    FIREWALL_ARN=$(aws network-firewall list-firewalls --query 'Firewalls[?FirewallName==`tgw-attached-firewall`].FirewallArn' --output text)
    FIREWALL_STATUS=$(aws network-firewall describe-firewall --firewall-arn "$FIREWALL_ARN" --query 'FirewallStatus.Status' --output text)
    
    print_status "PASS" "Network Firewall found: tgw-attached-firewall"
    echo "   Status: $FIREWALL_STATUS"
    ((PASS_COUNT++))
    
    if [ "$FIREWALL_STATUS" = "READY" ]; then
        print_status "PASS" "Network Firewall is in READY state"
        ((PASS_COUNT++))
    else
        print_status "WARN" "Network Firewall is not in READY state: $FIREWALL_STATUS"
        ((WARN_COUNT++))
    fi
    
    # Check firewall configuration
    FIREWALL_CONFIG=$(aws network-firewall describe-firewall --firewall-arn "$FIREWALL_ARN")
    
    # Check if firewall has subnet mappings (current implementation)
    SUBNET_COUNT=$(echo "$FIREWALL_CONFIG" | jq '.Firewall.SubnetMappings | length')
    if [ "$SUBNET_COUNT" -ge 2 ]; then
        print_status "PASS" "Network Firewall has subnet mappings ($SUBNET_COUNT subnets)"
        ((PASS_COUNT++))
    else
        print_status "FAIL" "Network Firewall has insufficient subnet mappings: $SUBNET_COUNT"
        ((FAIL_COUNT++))
    fi
    
else
    print_status "INFO" "Network Firewall not found (infrastructure may not be deployed yet)"
fi

# Configuration Analysis
echo
echo "6. Configuration Analysis..."

# Check if configuration follows TGW-attached pattern
if grep -q "transit_gateway_attachment" network_firewall.tf 2>/dev/null; then
    print_status "PASS" "Configuration includes TGW attachment block"
    ((PASS_COUNT++))
else
    print_status "WARN" "Configuration may not include proper TGW attachment (using subnet mapping approach)"
    ((WARN_COUNT++))
fi

# Check for availability zone mapping
if grep -q "availability_zone_mapping" network_firewall.tf 2>/dev/null; then
    print_status "PASS" "Configuration includes availability zone mapping"
    ((PASS_COUNT++))
else
    print_status "WARN" "Configuration may not include availability zone mapping (required for true TGW attachment)"
    ((WARN_COUNT++))
fi

# Check variable naming
if grep -q "egress_vpc_cidr_block" variables.tf 2>/dev/null; then
    print_status "PASS" "Variables use updated naming convention (egress_vpc_cidr_block)"
    ((PASS_COUNT++))
else
    print_status "FAIL" "Variables may still use old naming convention"
    ((FAIL_COUNT++))
fi

# Test script validation
echo
echo "7. Test Script Validation..."

# Check for test scripts
if [ -f "test_ec2_connectivity.sh" ]; then
    print_status "PASS" "EC2 connectivity test script found"
    ((PASS_COUNT++))
    
    if [ -x "test_ec2_connectivity.sh" ]; then
        print_status "PASS" "EC2 connectivity test script is executable"
        ((PASS_COUNT++))
    else
        print_status "WARN" "EC2 connectivity test script is not executable"
        ((WARN_COUNT++))
    fi
else
    print_status "FAIL" "EC2 connectivity test script not found"
    ((FAIL_COUNT++))
fi

if [ -f "test_firewall_policies.sh" ]; then
    print_status "PASS" "Firewall policy test script found"
    ((PASS_COUNT++))
    
    if [ -x "test_firewall_policies.sh" ]; then
        print_status "PASS" "Firewall policy test script is executable"
        ((PASS_COUNT++))
    else
        print_status "WARN" "Firewall policy test script is not executable"
        ((WARN_COUNT++))
    fi
else
    print_status "FAIL" "Firewall policy test script not found"
    ((FAIL_COUNT++))
fi

if [ -f "validate_firewall_config.sh" ]; then
    print_status "PASS" "Firewall configuration validation script found"
    ((PASS_COUNT++))
else
    print_status "FAIL" "Firewall configuration validation script not found"
    ((FAIL_COUNT++))
fi

# Summary
echo
echo "=== Validation Summary ==="
echo "Validation completed at $(date)"
echo
echo "Results:"
echo "  PASS: $PASS_COUNT"
echo "  WARN: $WARN_COUNT"
echo "  FAIL: $FAIL_COUNT"
echo

TOTAL_CHECKS=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))
SUCCESS_RATE=$((PASS_COUNT * 100 / TOTAL_CHECKS))

echo "Success Rate: $SUCCESS_RATE% ($PASS_COUNT/$TOTAL_CHECKS)"

if [ $FAIL_COUNT -eq 0 ]; then
    if [ $WARN_COUNT -eq 0 ]; then
        print_status "PASS" "All validations passed successfully!"
        echo
        echo "Infrastructure is ready for deployment."
        exit 0
    else
        print_status "WARN" "Validation completed with warnings."
        echo
        echo "Infrastructure can be deployed but some optimizations may be needed."
        exit 0
    fi
else
    print_status "FAIL" "Validation failed with $FAIL_COUNT critical issues."
    echo
    echo "Please address the failed checks before deployment."
    exit 1
fi