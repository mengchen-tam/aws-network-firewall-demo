#!/bin/bash

# Network Firewall Policy Testing Script
# This script tests the preserved security policies in the TGW-attached Network Firewall

set -e

echo "=========================================="
echo "Network Firewall Policy Testing Script"
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

# Function to get instance IDs
get_instance_ids() {
    print_status "INFO" "Getting EC2 instance IDs..."
    
    SPOKE1_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=spoke_vpc_vm_*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
    
    SPOKE2_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=spoke_vpc_2_vm_*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)
    
    if [ -z "$SPOKE1_INSTANCES" ] || [ -z "$SPOKE2_INSTANCES" ]; then
        print_status "FAIL" "Could not find running EC2 instances. Please ensure infrastructure is deployed."
        exit 1
    fi
    
    SPOKE1_INSTANCE=$(echo $SPOKE1_INSTANCES | cut -d' ' -f1)
    SPOKE2_INSTANCE=$(echo $SPOKE2_INSTANCES | cut -d' ' -f1)
    
    print_status "INFO" "Using Spoke VPC 1 instance: $SPOKE1_INSTANCE"
    print_status "INFO" "Using Spoke VPC 2 instance: $SPOKE2_INSTANCE"
}

# Function to test ICMP connectivity (should be allowed)
test_icmp_allow() {
    print_status "INFO" "Testing ICMP allow rule..."
    
    # Test inter-VPC ICMP (should work)
    print_status "INFO" "Testing inter-VPC ICMP connectivity..."
    
    # Get private IP of spoke2 instance
    SPOKE2_IP=$(aws ec2 describe-instances \
        --instance-ids $SPOKE2_INSTANCE \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text)
    
    # Test ping from spoke1 to spoke2
    PING_RESULT=$(aws ssm send-command \
        --instance-ids $SPOKE1_INSTANCE \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["ping -c 3 '$SPOKE2_IP' && echo PING_SUCCESS || echo PING_FAILED"]' \
        --query 'Command.CommandId' \
        --output text)
    
    # Wait for command to complete
    sleep 10
    
    PING_OUTPUT=$(aws ssm get-command-invocation \
        --command-id $PING_RESULT \
        --instance-id $SPOKE1_INSTANCE \
        --query 'StandardOutputContent' \
        --output text)
    
    if echo "$PING_OUTPUT" | grep -q "PING_SUCCESS"; then
        print_status "PASS" "Inter-VPC ICMP connectivity works (firewall allows ICMP)"
    else
        print_status "FAIL" "Inter-VPC ICMP connectivity failed"
        echo "Output: $PING_OUTPUT"
    fi
    
    # Test internet ICMP (should work - ICMP allowed)
    print_status "INFO" "Testing internet ICMP connectivity..."
    
    INTERNET_PING_RESULT=$(aws ssm send-command \
        --instance-ids $SPOKE1_INSTANCE \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["ping -c 3 8.8.8.8 && echo INTERNET_PING_SUCCESS || echo INTERNET_PING_FAILED"]' \
        --query 'Command.CommandId' \
        --output text)
    
    # Wait for command to complete
    sleep 10
    
    INTERNET_PING_OUTPUT=$(aws ssm get-command-invocation \
        --command-id $INTERNET_PING_RESULT \
        --instance-id $SPOKE1_INSTANCE \
        --query 'StandardOutputContent' \
        --output text)
    
    if echo "$INTERNET_PING_OUTPUT" | grep -q "INTERNET_PING_SUCCESS"; then
        print_status "PASS" "Internet ICMP connectivity works (firewall allows ICMP)"
    else
        print_status "FAIL" "Internet ICMP connectivity failed"
        echo "Output: $INTERNET_PING_OUTPUT"
    fi
}

# Function to test URL blocking rule (www.baidu.com should be blocked)
test_url_blocking() {
    print_status "INFO" "Testing URL blocking rule for www.baidu.com..."
    
    # Test HTTP request to blocked domain (should fail)
    CURL_RESULT=$(aws ssm send-command \
        --instance-ids $SPOKE1_INSTANCE \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["timeout 30 curl -s -o /dev/null -w \"%{http_code}\" http://www.baidu.com || echo BLOCKED"]' \
        --query 'Command.CommandId' \
        --output text)
    
    # Wait for command to complete
    sleep 35
    
    CURL_OUTPUT=$(aws ssm get-command-invocation \
        --command-id $CURL_RESULT \
        --instance-id $SPOKE1_INSTANCE \
        --query 'StandardOutputContent' \
        --output text)
    
    if echo "$CURL_OUTPUT" | grep -q "BLOCKED" || echo "$CURL_OUTPUT" | grep -q "000"; then
        print_status "PASS" "www.baidu.com is blocked by firewall (URL blocking rule works)"
    else
        print_status "FAIL" "www.baidu.com was not blocked (HTTP code: $CURL_OUTPUT)"
    fi
    
    # Test HTTPS request to blocked domain (should also fail)
    CURL_HTTPS_RESULT=$(aws ssm send-command \
        --instance-ids $SPOKE1_INSTANCE \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["timeout 30 curl -s -o /dev/null -w \"%{http_code}\" https://www.baidu.com || echo BLOCKED"]' \
        --query 'Command.CommandId' \
        --output text)
    
    # Wait for command to complete
    sleep 35
    
    CURL_HTTPS_OUTPUT=$(aws ssm get-command-invocation \
        --command-id $CURL_HTTPS_RESULT \
        --instance-id $SPOKE1_INSTANCE \
        --query 'StandardOutputContent' \
        --output text)
    
    if echo "$CURL_HTTPS_OUTPUT" | grep -q "BLOCKED" || echo "$CURL_HTTPS_OUTPUT" | grep -q "000"; then
        print_status "PASS" "https://www.baidu.com is blocked by firewall (TLS_SNI blocking works)"
    else
        print_status "FAIL" "https://www.baidu.com was not blocked (HTTP code: $CURL_HTTPS_OUTPUT)"
    fi
}

# Function to test allowed URL access
test_allowed_url() {
    print_status "INFO" "Testing allowed URL access..."
    
    # Test HTTP request to allowed domain (should work)
    ALLOWED_CURL_RESULT=$(aws ssm send-command \
        --instance-ids $SPOKE1_INSTANCE \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["timeout 30 curl -s -o /dev/null -w \"%{http_code}\" http://www.qq.com"]' \
        --query 'Command.CommandId' \
        --output text)
    
    # Wait for command to complete
    sleep 35
    
    ALLOWED_CURL_OUTPUT=$(aws ssm get-command-invocation \
        --command-id $ALLOWED_CURL_RESULT \
        --instance-id $SPOKE1_INSTANCE \
        --query 'StandardOutputContent' \
        --output text)
    
    if echo "$ALLOWED_CURL_OUTPUT" | grep -q "200"; then
        print_status "PASS" "www.qq.com is accessible (allowed URLs work)"
    else
        print_status "INFO" "www.qq.com response code: $ALLOWED_CURL_OUTPUT (may be expected depending on firewall rules)"
    fi
}

# Function to verify firewall configuration
verify_firewall_config() {
    print_status "INFO" "Verifying Network Firewall configuration..."
    
    # Check if firewall exists and is active
    FIREWALL_STATUS=$(aws network-firewall describe-firewall \
        --firewall-name "tgw-attached-firewall" \
        --query 'Firewall.FirewallStatus' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$FIREWALL_STATUS" = "READY" ]; then
        print_status "PASS" "Network Firewall is in READY state"
    else
        print_status "FAIL" "Network Firewall status: $FIREWALL_STATUS"
    fi
    
    # Check firewall policy
    POLICY_ARN=$(aws network-firewall describe-firewall \
        --firewall-name "tgw-attached-firewall" \
        --query 'Firewall.FirewallPolicyArn' \
        --output text 2>/dev/null || echo "NOT_FOUND")
    
    if [ "$POLICY_ARN" != "NOT_FOUND" ]; then
        print_status "PASS" "Firewall policy is attached: $(basename $POLICY_ARN)"
        
        # Check rule groups in policy
        RULE_GROUPS=$(aws network-firewall describe-firewall-policy \
            --firewall-policy-arn "$POLICY_ARN" \
            --query 'FirewallPolicy.StatefulRuleGroupReferences[].ResourceArn' \
            --output text)
        
        print_status "INFO" "Attached rule groups:"
        for rule_group in $RULE_GROUPS; do
            echo "  - $(basename $rule_group)"
        done
        
        # Verify specific rule groups exist
        if echo "$RULE_GROUPS" | grep -q "allow-icmp-rule-group"; then
            print_status "PASS" "ICMP allow rule group is present"
        else
            print_status "FAIL" "ICMP allow rule group is missing"
        fi
        
        if echo "$RULE_GROUPS" | grep -q "block-url-rule-group"; then
            print_status "PASS" "URL blocking rule group is present"
        else
            print_status "FAIL" "URL blocking rule group is missing"
        fi
        
        if echo "$RULE_GROUPS" | grep -q "MalwareDomainsStrictOrder"; then
            print_status "PASS" "AWS managed MalwareDomains rule group is present"
        else
            print_status "FAIL" "AWS managed MalwareDomains rule group is missing"
        fi
        
        if echo "$RULE_GROUPS" | grep -q "ThreatSignaturesBotnetStrictOrder"; then
            print_status "PASS" "AWS managed ThreatSignaturesBotnet rule group is present"
        else
            print_status "FAIL" "AWS managed ThreatSignaturesBotnet rule group is missing"
        fi
    else
        print_status "FAIL" "Could not retrieve firewall policy"
    fi
}

# Function to check firewall logs (if available)
check_firewall_logs() {
    print_status "INFO" "Checking for firewall logs..."
    
    # This is informational - logs may not be configured
    LOG_GROUP="/aws/networkfirewall/flowlogs"
    
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP" --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q "$LOG_GROUP"; then
        print_status "INFO" "Firewall logs are configured in CloudWatch"
        
        # Get recent log entries (last 5 minutes)
        RECENT_LOGS=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP" \
            --start-time $(date -d '5 minutes ago' +%s)000 \
            --query 'events[0:5].message' \
            --output text 2>/dev/null || echo "")
        
        if [ -n "$RECENT_LOGS" ]; then
            print_status "INFO" "Recent firewall activity detected in logs"
        else
            print_status "INFO" "No recent firewall activity in logs (this may be normal)"
        fi
    else
        print_status "INFO" "Firewall logs are not configured (optional feature)"
    fi
}

# Main execution
main() {
    echo "Starting Network Firewall policy testing..."
    echo ""
    
    # Check AWS CLI availability
    if ! command -v aws &> /dev/null; then
        print_status "FAIL" "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Verify AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_status "FAIL" "AWS credentials are not configured or invalid"
        exit 1
    fi
    
    print_status "PASS" "AWS CLI and credentials are configured"
    echo ""
    
    # Get instance IDs
    get_instance_ids
    echo ""
    
    # Verify firewall configuration
    verify_firewall_config
    echo ""
    
    # Test ICMP allow rule
    test_icmp_allow
    echo ""
    
    # Test URL blocking rule
    test_url_blocking
    echo ""
    
    # Test allowed URL access
    test_allowed_url
    echo ""
    
    # Check firewall logs
    check_firewall_logs
    echo ""
    
    print_status "INFO" "Network Firewall policy testing completed!"
    echo ""
    echo "Summary:"
    echo "- ICMP traffic should be allowed (inter-VPC and internet)"
    echo "- www.baidu.com should be blocked (HTTP and HTTPS)"
    echo "- Other URLs should be allowed (unless blocked by AWS managed rules)"
    echo "- All rule groups should be present and active"
}

# Run main function
main "$@"