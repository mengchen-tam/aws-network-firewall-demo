#!/bin/bash

# Network Firewall Configuration Validation Script
# This script validates that the firewall policy and rule groups are preserved correctly

set -e

echo "=========================================="
echo "Network Firewall Configuration Validation"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    case $status in
        "PASS")
            echo -e "${GREEN}[PASS]${NC} $message"
            ;;
        "FAIL")
            echo -e "${RED}[FAIL]${NC} $message"
            ;;
        "INFO")
            echo -e "${YELLOW}[INFO]${NC} $message"
            ;;
    esac
}

# Function to validate ICMP allow rule group
validate_icmp_rule_group() {
    print_status "INFO" "Validating ICMP allow rule group configuration..."
    
    # Check if the rule group exists in network_firewall.tf
    if grep -q "aws_networkfirewall_rule_group.*allow_icmp" network_firewall.tf; then
        print_status "PASS" "ICMP allow rule group resource exists"
        
        # Check rule configuration
        if grep -A 30 "resource.*allow_icmp" network_firewall.tf | grep -q 'protocol.*=.*"ICMP"'; then
            print_status "PASS" "ICMP protocol is configured correctly"
        else
            print_status "FAIL" "ICMP protocol configuration is missing or incorrect"
        fi
        
        if grep -A 30 "resource.*allow_icmp" network_firewall.tf | grep -q 'action.*=.*"PASS"'; then
            print_status "PASS" "ICMP allow action is configured correctly"
        else
            print_status "FAIL" "ICMP allow action is missing or incorrect"
        fi
        
        if grep -A 20 "resource.*allow_icmp" network_firewall.tf | grep -q "HOME_NET"; then
            print_status "PASS" "HOME_NET variable is configured for ICMP rule"
        else
            print_status "FAIL" "HOME_NET variable is missing from ICMP rule"
        fi
    else
        print_status "FAIL" "ICMP allow rule group resource is missing"
    fi
}

# Function to validate URL blocking rule group
validate_url_blocking_rule_group() {
    print_status "INFO" "Validating URL blocking rule group configuration..."
    
    # Check if the rule group exists in network_firewall.tf
    if grep -q "aws_networkfirewall_rule_group.*block_url" network_firewall.tf; then
        print_status "PASS" "URL blocking rule group resource exists"
        
        # Check rule configuration
        if grep -A 20 "resource.*block_url" network_firewall.tf | grep -q "DENYLIST"; then
            print_status "PASS" "DENYLIST configuration is correct"
        else
            print_status "FAIL" "DENYLIST configuration is missing or incorrect"
        fi
        
        if grep -A 20 "resource.*block_url" network_firewall.tf | grep -q "HTTP_HOST.*TLS_SNI"; then
            print_status "PASS" "HTTP_HOST and TLS_SNI target types are configured"
        else
            print_status "FAIL" "HTTP_HOST and TLS_SNI target types are missing"
        fi
        
        if grep -A 20 "resource.*block_url" network_firewall.tf | grep -q "www.baidu.com"; then
            print_status "PASS" "www.baidu.com is configured in block list"
        else
            print_status "FAIL" "www.baidu.com is missing from block list"
        fi
    else
        print_status "FAIL" "URL blocking rule group resource is missing"
    fi
}

# Function to validate firewall policy
validate_firewall_policy() {
    print_status "INFO" "Validating firewall policy configuration..."
    
    # Check if the policy exists
    if grep -q "aws_networkfirewall_firewall_policy.*example_policy" network_firewall.tf; then
        print_status "PASS" "Firewall policy resource exists"
        
        # Check stateless default actions
        if grep -A 30 "resource.*example_policy" network_firewall.tf | grep -q "aws:forward_to_sfe"; then
            print_status "PASS" "Stateless default action is configured to forward to stateful engine"
        else
            print_status "FAIL" "Stateless default action is missing or incorrect"
        fi
        
        # Check rule order
        if grep -A 30 "resource.*example_policy" network_firewall.tf | grep -q "STRICT_ORDER"; then
            print_status "PASS" "Strict order rule processing is configured"
        else
            print_status "FAIL" "Strict order rule processing is missing"
        fi
        
        # Check AWS managed rule groups
        if grep -A 50 "resource.*example_policy" network_firewall.tf | grep -q "MalwareDomainsStrictOrder"; then
            print_status "PASS" "AWS managed MalwareDomains rule group is referenced"
        else
            print_status "FAIL" "AWS managed MalwareDomains rule group is missing"
        fi
        
        if grep -A 50 "resource.*example_policy" network_firewall.tf | grep -q "ThreatSignaturesBotnetStrictOrder"; then
            print_status "PASS" "AWS managed ThreatSignaturesBotnet rule group is referenced"
        else
            print_status "FAIL" "AWS managed ThreatSignaturesBotnet rule group is missing"
        fi
        
        # Check custom rule group references
        if grep -A 50 "resource.*example_policy" network_firewall.tf | grep -q "aws_networkfirewall_rule_group.block_url.arn"; then
            print_status "PASS" "URL blocking rule group is referenced in policy"
        else
            print_status "FAIL" "URL blocking rule group reference is missing"
        fi
        
        if grep -A 50 "resource.*example_policy" network_firewall.tf | grep -q "aws_networkfirewall_rule_group.allow_icmp.arn"; then
            print_status "PASS" "ICMP allow rule group is referenced in policy"
        else
            print_status "FAIL" "ICMP allow rule group reference is missing"
        fi
        
        # Check priority values
        if grep -A 50 "resource.*example_policy" network_firewall.tf | grep -A 2 "MalwareDomainsStrictOrder" | grep -q "priority.*50"; then
            print_status "PASS" "MalwareDomains rule group has correct priority (50)"
        else
            print_status "INFO" "MalwareDomains rule group priority may need verification"
        fi
        
        if grep -A 50 "resource.*example_policy" network_firewall.tf | grep -A 2 "ThreatSignaturesBotnetStrictOrder" | grep -q "priority.*75"; then
            print_status "PASS" "ThreatSignaturesBotnet rule group has correct priority (75)"
        else
            print_status "INFO" "ThreatSignaturesBotnet rule group priority may need verification"
        fi
    else
        print_status "FAIL" "Firewall policy resource is missing"
    fi
}

# Function to validate firewall resource configuration
validate_firewall_resource() {
    print_status "INFO" "Validating firewall resource configuration..."
    
    # Check if the firewall resource exists
    if grep -q "aws_networkfirewall_firewall.*tgw_attached" network_firewall.tf; then
        print_status "PASS" "TGW-attached firewall resource exists"
        
        # Check policy reference
        if grep -A 20 "resource.*tgw_attached" network_firewall.tf | grep -q "aws_networkfirewall_firewall_policy.example_policy.arn"; then
            print_status "PASS" "Firewall policy is correctly referenced"
        else
            print_status "FAIL" "Firewall policy reference is missing or incorrect"
        fi
        
        # Check subnet mapping (current implementation)
        if grep -A 20 "resource.*tgw_attached" network_firewall.tf | grep -q "subnet_mapping"; then
            print_status "INFO" "Firewall uses subnet mapping (current implementation)"
        else
            print_status "INFO" "Firewall may use availability zone mapping (TGW-attached mode)"
        fi
        
        # Check dependencies
        if grep -A 30 "resource.*tgw_attached" network_firewall.tf | grep -q "depends_on"; then
            print_status "PASS" "Firewall resource has dependency configuration"
        else
            print_status "INFO" "Firewall resource may need explicit dependencies"
        fi
    else
        print_status "FAIL" "TGW-attached firewall resource is missing"
    fi
}

# Function to validate CIDR block consistency
validate_cidr_blocks() {
    print_status "INFO" "Validating CIDR block consistency..."
    
    # Check HOME_NET CIDR in rule groups
    HOME_NET_CIDR=$(grep -A 10 "HOME_NET" network_firewall.tf | grep "definition" | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
    
    if [ -n "$HOME_NET_CIDR" ]; then
        print_status "INFO" "HOME_NET CIDR is set to: $HOME_NET_CIDR"
        
        # Check if it matches parent CIDR from variables
        PARENT_CIDR=$(grep -A 3 "parent_cidr_block" variables.tf | grep "default" | sed 's/.*"\([^"]*\)".*/\1/')
        
        if [ "$HOME_NET_CIDR" = "$PARENT_CIDR" ]; then
            print_status "PASS" "HOME_NET CIDR matches parent CIDR block"
        else
            if [ -n "$PARENT_CIDR" ]; then
                print_status "INFO" "HOME_NET CIDR ($HOME_NET_CIDR) differs from parent CIDR ($PARENT_CIDR)"
            else
                print_status "INFO" "Could not determine parent CIDR from variables.tf"
            fi
        fi
    else
        print_status "FAIL" "HOME_NET CIDR could not be determined"
    fi
}

# Function to run Terraform validation
run_terraform_validation() {
    print_status "INFO" "Running Terraform validation..."
    
    if command -v terraform &> /dev/null; then
        # Initialize if needed
        if [ ! -d ".terraform" ]; then
            print_status "INFO" "Initializing Terraform..."
            terraform init -backend=false > /dev/null 2>&1
        fi
        
        # Run terraform validate
        if terraform validate > /dev/null 2>&1; then
            print_status "PASS" "Terraform configuration is valid"
        else
            print_status "FAIL" "Terraform configuration has validation errors"
            terraform validate
        fi
        
        # Run terraform plan (dry run)
        print_status "INFO" "Running Terraform plan (dry run)..."
        if terraform plan -out=/dev/null > /dev/null 2>&1; then
            print_status "PASS" "Terraform plan completed successfully"
        else
            print_status "INFO" "Terraform plan may require AWS credentials or have dependency issues"
        fi
    else
        print_status "INFO" "Terraform not found - skipping Terraform validation"
    fi
}

# Main execution
main() {
    echo "Starting Network Firewall configuration validation..."
    echo ""
    
    # Check if we're in the right directory
    if [ ! -f "network_firewall.tf" ]; then
        print_status "FAIL" "network_firewall.tf not found. Please run this script from the project directory."
        exit 1
    fi
    
    print_status "PASS" "Found network_firewall.tf configuration file"
    echo ""
    
    # Validate ICMP rule group
    validate_icmp_rule_group
    echo ""
    
    # Validate URL blocking rule group
    validate_url_blocking_rule_group
    echo ""
    
    # Validate firewall policy
    validate_firewall_policy
    echo ""
    
    # Validate firewall resource
    validate_firewall_resource
    echo ""
    
    # Validate CIDR blocks
    validate_cidr_blocks
    echo ""
    
    # Run Terraform validation
    run_terraform_validation
    echo ""
    
    print_status "INFO" "Network Firewall configuration validation completed!"
    echo ""
    echo "Summary:"
    echo "- ICMP allow rule group should be properly configured"
    echo "- URL blocking rule group should block www.baidu.com"
    echo "- Firewall policy should reference all rule groups with correct priorities"
    echo "- AWS managed rule groups should be included"
    echo "- Terraform configuration should be valid"
}

# Run main function
main "$@"