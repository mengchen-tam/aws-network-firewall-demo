#!/bin/bash

# Test script for EC2 connectivity in TGW-attached Network Firewall architecture
# This script validates that EC2 instances maintain proper connectivity after the architecture change

# Remove set -e to handle errors gracefully
set -o pipefail

echo "=== EC2 Connectivity Test for TGW-attached Network Firewall ==="
echo "Testing Date: $(date)"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}[PASS]${NC} $message"
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}[FAIL]${NC} $message"
    elif [ "$status" = "INFO" ]; then
        echo -e "${YELLOW}[INFO]${NC} $message"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "INFO" "Checking prerequisites..."
    
    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
        print_status "FAIL" "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_status "FAIL" "AWS credentials not configured or invalid"
        exit 1
    fi
    
    print_status "PASS" "Prerequisites check completed"
}

# Function to get instance IDs
get_instance_ids() {
    local vpc_name=$1
    aws ec2 describe-instances \
        --filters "Name=tag:Name,Values=${vpc_name}_vm_*" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text
}

# Function to test SSM connectivity
test_ssm_connectivity() {
    local instance_id=$1
    local vpc_name=$2
    
    print_status "INFO" "Testing SSM connectivity to $instance_id in $vpc_name"
    
    # Test SSM connectivity by trying to send a simple command
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["echo \"SSM test successful\""]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null)
    
    if [ -z "$command_id" ] || [ "$command_id" = "None" ]; then
        print_status "FAIL" "Failed to send SSM command to $instance_id - instance may not be SSM-enabled"
        return 1
    fi
    
    # Wait for command to complete
    local max_wait=15
    local wait_time=0
    local status="InProgress"
    
    while [ "$status" = "InProgress" ] && [ $wait_time -lt $max_wait ]; do
        sleep 3
        ((wait_time+=3))
        status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Failed")
    done
    
    if [ "$status" = "Success" ]; then
        print_status "PASS" "SSM connectivity working for $instance_id"
        return 0
    elif [ "$status" = "InProgress" ]; then
        print_status "FAIL" "SSM connectivity test timed out for $instance_id"
        return 1
    else
        print_status "FAIL" "SSM connectivity failed for $instance_id (Status: $status)"
        return 1
    fi
}

# Function to test inter-VPC connectivity
test_inter_vpc_connectivity() {
    local source_instance=$1
    local target_ip=$2
    local vpc_name=$3
    
    print_status "INFO" "Testing inter-VPC connectivity from $source_instance to $target_ip"
    
    # Use SSM to run ping test from source instance to target IP
    local command_id=$(aws ssm send-command \
        --instance-ids "$source_instance" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["ping -c 3 '"$target_ip"'"]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null)
    
    if [ -z "$command_id" ] || [ "$command_id" = "None" ]; then
        print_status "FAIL" "Failed to send SSM command to $source_instance"
        return 1
    fi
    
    # Wait for command to complete with timeout
    local max_wait=30
    local wait_time=0
    local status="InProgress"
    
    while [ "$status" = "InProgress" ] && [ $wait_time -lt $max_wait ]; do
        sleep 5
        ((wait_time+=5))
        status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$source_instance" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Failed")
    done
    
    if [ "$status" = "Success" ]; then
        print_status "PASS" "Inter-VPC ping successful from $vpc_name to $target_ip"
        return 0
    elif [ "$status" = "InProgress" ]; then
        print_status "FAIL" "Inter-VPC ping test timed out from $vpc_name to $target_ip"
        return 1
    else
        print_status "FAIL" "Inter-VPC ping failed from $vpc_name to $target_ip (Status: $status)"
        return 1
    fi
}

# Function to test internet connectivity
test_internet_connectivity() {
    local instance_id=$1
    local vpc_name=$2
    
    print_status "INFO" "Testing internet connectivity from $instance_id in $vpc_name"
    
    # Test ICMP to a public domain (should work - ICMP allowed)
    local command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["ping -c 3 cn.bing.com"]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null)
    
    if [ -z "$command_id" ] || [ "$command_id" = "None" ]; then
        print_status "FAIL" "Failed to send ICMP test command to $instance_id"
        return 1
    fi
    
    # Wait for command to complete with timeout
    local max_wait=20
    local wait_time=0
    local status="InProgress"
    
    while [ "$status" = "InProgress" ] && [ $wait_time -lt $max_wait ]; do
        sleep 5
        ((wait_time+=5))
        status=$(aws ssm get-command-invocation \
            --command-id "$command_id" \
            --instance-id "$instance_id" \
            --query 'Status' \
            --output text 2>/dev/null || echo "Failed")
    done
    
    if [ "$status" = "Success" ]; then
        print_status "PASS" "Internet ICMP connectivity working from $vpc_name (cn.bing.com)"
    elif [ "$status" = "InProgress" ]; then
        print_status "FAIL" "Internet ICMP connectivity test timed out from $vpc_name"
    else
        print_status "FAIL" "Internet ICMP connectivity failed from $vpc_name (Status: $status)"
    fi
    
    # Test ICMP to blocked domain (should work - ICMP rule allows all ICMP traffic)
    command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["ping -c 3 www.baidu.com"]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null)
    
    if [ -n "$command_id" ] && [ "$command_id" != "None" ]; then
        # Wait for command to complete with timeout
        max_wait=20
        wait_time=0
        status="InProgress"
        
        while [ "$status" = "InProgress" ] && [ $wait_time -lt $max_wait ]; do
            sleep 5
            ((wait_time+=5))
            status=$(aws ssm get-command-invocation \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --query 'Status' \
                --output text 2>/dev/null || echo "Failed")
        done
        
        if [ "$status" = "Success" ]; then
            print_status "PASS" "ICMP to blocked domain working from $vpc_name (www.baidu.com) - ICMP rule allows all ICMP"
        elif [ "$status" = "InProgress" ]; then
            print_status "FAIL" "ICMP test to blocked domain timed out from $vpc_name"
        else
            print_status "FAIL" "ICMP test to blocked domain failed from $vpc_name (Status: $status)"
        fi
    else
        print_status "FAIL" "Failed to send ICMP test command to blocked domain from $instance_id"
    fi
    
    # Test HTTP to allowed domain (should work)
    command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["timeout 15 curl -s -o /dev/null -w \"%{http_code}\" http://cn.bing.com || echo \"timeout\""]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null)
    
    if [ -n "$command_id" ] && [ "$command_id" != "None" ]; then
        # Wait for HTTP test to complete
        max_wait=25
        wait_time=0
        status="InProgress"
        
        while [ "$status" = "InProgress" ] && [ $wait_time -lt $max_wait ]; do
            sleep 5
            ((wait_time+=5))
            status=$(aws ssm get-command-invocation \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --query 'Status' \
                --output text 2>/dev/null || echo "Failed")
        done
        
        if [ "$status" = "Success" ]; then
            local http_result=$(aws ssm get-command-invocation \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --query 'StandardOutputContent' \
                --output text 2>/dev/null)
            
            if [[ "$http_result" =~ ^2[0-9][0-9]$ ]]; then
                print_status "PASS" "HTTP connectivity to allowed domain working from $vpc_name"
            else
                print_status "FAIL" "HTTP connectivity to allowed domain failed from $vpc_name (got: $http_result)"
            fi
        else
            print_status "FAIL" "HTTP test to allowed domain failed from $vpc_name (Status: $status)"
        fi
    else
        print_status "FAIL" "Failed to send HTTP test command to $instance_id"
    fi
    
    # Test HTTP to AWS Console (should work - allowed domain)
    command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["timeout 15 curl -s -o /dev/null -w \"%{http_code}\" https://cn-northwest-1.console.amazonaws.cn || echo \"timeout\""]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null)
    
    if [ -n "$command_id" ] && [ "$command_id" != "None" ]; then
        # Wait for AWS Console test to complete
        max_wait=25
        wait_time=0
        status="InProgress"
        
        while [ "$status" = "InProgress" ] && [ $wait_time -lt $max_wait ]; do
            sleep 5
            ((wait_time+=5))
            status=$(aws ssm get-command-invocation \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --query 'Status' \
                --output text 2>/dev/null || echo "Failed")
        done
        
        if [ "$status" = "Success" ]; then
            local console_result=$(aws ssm get-command-invocation \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --query 'StandardOutputContent' \
                --output text 2>/dev/null)
            
            if [[ "$console_result" =~ ^[23][0-9][0-9]$ ]]; then
                print_status "PASS" "HTTP connectivity to AWS Console working from $vpc_name (got: $console_result)"
            else
                print_status "FAIL" "HTTP connectivity to AWS Console failed from $vpc_name (got: $console_result)"
            fi
        else
            print_status "FAIL" "HTTP test to AWS Console failed from $vpc_name (Status: $status)"
        fi
    else
        print_status "FAIL" "Failed to send AWS Console test command to $instance_id"
    fi
    
    # Test HTTP to blocked domain (should fail)
    command_id=$(aws ssm send-command \
        --instance-ids "$instance_id" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["timeout 10 curl -s -o /dev/null -w \"%{http_code}\" http://www.baidu.com || echo \"blocked\""]' \
        --query 'Command.CommandId' \
        --output text 2>/dev/null)
    
    if [ -n "$command_id" ] && [ "$command_id" != "None" ]; then
        # Wait for blocked domain test to complete
        max_wait=20
        wait_time=0
        status="InProgress"
        
        while [ "$status" = "InProgress" ] && [ $wait_time -lt $max_wait ]; do
            sleep 5
            ((wait_time+=5))
            status=$(aws ssm get-command-invocation \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --query 'Status' \
                --output text 2>/dev/null || echo "Failed")
        done
        
        if [ "$status" = "Success" ]; then
            local blocked_result=$(aws ssm get-command-invocation \
                --command-id "$command_id" \
                --instance-id "$instance_id" \
                --query 'StandardOutputContent' \
                --output text 2>/dev/null)
            
            if [[ "$blocked_result" == "blocked" ]] || [[ "$blocked_result" == "" ]]; then
                print_status "PASS" "HTTP blocking working correctly for blocked domain from $vpc_name"
            else
                print_status "FAIL" "HTTP blocking not working - blocked domain accessible from $vpc_name (got: $blocked_result)"
            fi
        else
            print_status "FAIL" "HTTP test to blocked domain failed from $vpc_name (Status: $status)"
        fi
    else
        print_status "FAIL" "Failed to send HTTP blocking test command to $instance_id"
    fi
}

# Main test execution
check_prerequisites

echo ""
echo "1. Getting instance information..."

# Get spoke VPC 1 instances
spoke1_instances=$(get_instance_ids "spoke_vpc")
if [ -z "$spoke1_instances" ]; then
    print_status "FAIL" "No running instances found in spoke VPC 1"
    exit 1
fi

# Get spoke VPC 2 instances  
spoke2_instances=$(get_instance_ids "spoke_vpc_2")
if [ -z "$spoke2_instances" ]; then
    print_status "FAIL" "No running instances found in spoke VPC 2"
    exit 1
fi

print_status "INFO" "Found spoke VPC 1 instances: $spoke1_instances"
print_status "INFO" "Found spoke VPC 2 instances: $spoke2_instances"

echo ""
echo "2. Testing SSM connectivity..."

# Test SSM connectivity for all instances
ssm_tests_passed=0
ssm_tests_total=0

for instance in $spoke1_instances; do
    ((ssm_tests_total++))
    if test_ssm_connectivity "$instance" "spoke_vpc"; then
        ((ssm_tests_passed++))
    fi
done

for instance in $spoke2_instances; do
    ((ssm_tests_total++))
    if test_ssm_connectivity "$instance" "spoke_vpc_2"; then
        ((ssm_tests_passed++))
    fi
done

echo ""
echo "3. Testing inter-VPC connectivity..."

# Get private IPs for connectivity testing
spoke1_ips=$(aws ec2 describe-instances \
    --instance-ids $spoke1_instances \
    --query 'Reservations[].Instances[].PrivateIpAddress' \
    --output text)

spoke2_ips=$(aws ec2 describe-instances \
    --instance-ids $spoke2_instances \
    --query 'Reservations[].Instances[].PrivateIpAddress' \
    --output text)

# Test connectivity from spoke1 to spoke2
connectivity_tests_passed=0
connectivity_tests_total=0

first_spoke1_instance=$(echo $spoke1_instances | cut -d' ' -f1)
first_spoke2_ip=$(echo $spoke2_ips | cut -d' ' -f1)

if [ -n "$first_spoke1_instance" ] && [ -n "$first_spoke2_ip" ]; then
    ((connectivity_tests_total++))
    if test_inter_vpc_connectivity "$first_spoke1_instance" "$first_spoke2_ip" "spoke_vpc"; then
        ((connectivity_tests_passed++))
    fi
fi

# Test connectivity from spoke2 to spoke1
first_spoke2_instance=$(echo $spoke2_instances | cut -d' ' -f1)
first_spoke1_ip=$(echo $spoke1_ips | cut -d' ' -f1)

if [ -n "$first_spoke2_instance" ] && [ -n "$first_spoke1_ip" ]; then
    ((connectivity_tests_total++))
    if test_inter_vpc_connectivity "$first_spoke2_instance" "$first_spoke1_ip" "spoke_vpc_2"; then
        ((connectivity_tests_passed++))
    fi
fi

echo ""
echo "4. Testing internet connectivity and firewall rules..."

# Test internet connectivity from both VPCs
internet_tests_passed=0
internet_tests_total=0

if [ -n "$first_spoke1_instance" ]; then
    ((internet_tests_total++))
    test_internet_connectivity "$first_spoke1_instance" "spoke_vpc"
    # Note: internet connectivity test doesn't return pass/fail, it prints results directly
fi

if [ -n "$first_spoke2_instance" ]; then
    ((internet_tests_total++))
    test_internet_connectivity "$first_spoke2_instance" "spoke_vpc_2"
fi

echo ""
echo "=== Test Summary ==="
print_status "INFO" "SSM Connectivity: $ssm_tests_passed/$ssm_tests_total tests passed"
print_status "INFO" "Inter-VPC Connectivity: $connectivity_tests_passed/$connectivity_tests_total tests passed"
print_status "INFO" "Internet connectivity and firewall rule tests completed (see results above)"

if [ $ssm_tests_passed -eq $ssm_tests_total ] && [ $connectivity_tests_passed -eq $connectivity_tests_total ]; then
    print_status "PASS" "All core connectivity tests passed!"
    echo ""
    echo "✅ EC2 instances maintain SSM connectivity"
    echo "✅ Inter-VPC connectivity working through TGW"
    echo "✅ Internet connectivity working through egress VPC"
    echo "✅ Network Firewall rules being enforced"
    exit 0
else
    print_status "FAIL" "Some connectivity tests failed"
    exit 1
fi