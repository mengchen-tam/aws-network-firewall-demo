#!/bin/bash

# Master Test Execution Script for TGW-attached Network Firewall
# This script runs all verification tests in the recommended order and provides a comprehensive report

set -e

echo "============================================================================"
echo "TGW-attached Network Firewall - Complete Test Suite"
echo "============================================================================"
echo "Execution Date: $(date)"
echo "Architecture: Transit Gateway attached Network Firewall with spoke VPCs"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test tracking
TOTAL_SCRIPTS=3
PASSED_SCRIPTS=0
FAILED_SCRIPTS=0
TEST_RESULTS=()

# Function to print colored output
print_header() {
    echo -e "${CYAN}============================================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================================${NC}"
}

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
        "RUNNING")
            echo -e "${BLUE}[RUNNING]${NC} $message"
            ;;
    esac
}

# Function to run a test script and capture results
run_test_script() {
    local script_name=$1
    local script_description=$2
    
    print_header "Running: $script_description"
    print_status "RUNNING" "Executing $script_name..."
    
    if [ ! -f "$script_name" ]; then
        print_status "FAIL" "Test script $script_name not found"
        TEST_RESULTS+=("❌ $script_description - Script not found")
        ((FAILED_SCRIPTS++))
        return 1
    fi
    
    if [ ! -x "$script_name" ]; then
        print_status "INFO" "Making $script_name executable..."
        chmod +x "$script_name"
    fi
    
    # Run the script and capture exit code
    if ./"$script_name"; then
        print_status "PASS" "$script_description completed successfully"
        TEST_RESULTS+=("✅ $script_description - PASSED")
        ((PASSED_SCRIPTS++))
        return 0
    else
        print_status "FAIL" "$script_description failed"
        TEST_RESULTS+=("❌ $script_description - FAILED")
        ((FAILED_SCRIPTS++))
        return 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_header "Pre-Test Validation"
    
    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        print_status "FAIL" "AWS CLI is not installed or not in PATH"
        exit 1
    fi
    print_status "PASS" "AWS CLI is available"
    
    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        print_status "FAIL" "AWS credentials are not configured or invalid"
        exit 1
    fi
    print_status "PASS" "AWS credentials are configured"
    
    # Check if we're in the right directory
    if [ ! -f "network_firewall.tf" ]; then
        print_status "FAIL" "network_firewall.tf not found. Please run from project directory."
        exit 1
    fi
    print_status "PASS" "Running from correct project directory"
    
    # Check for test scripts
    local required_scripts=("validate_firewall_config.sh" "test_ec2_connectivity.sh" "test_firewall_policies.sh")
    local missing_scripts=()
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            missing_scripts+=("$script")
        fi
    done
    
    if [ ${#missing_scripts[@]} -gt 0 ]; then
        print_status "FAIL" "Missing test scripts: ${missing_scripts[*]}"
        exit 1
    fi
    print_status "PASS" "All required test scripts are present"
    
    echo ""
}

# Function to generate final report
generate_final_report() {
    print_header "FINAL TEST REPORT"
    
    echo "Test Execution Summary:"
    echo "- Total Test Scripts: $TOTAL_SCRIPTS"
    echo "- Passed: $PASSED_SCRIPTS"
    echo "- Failed: $FAILED_SCRIPTS"
    echo "- Success Rate: $(( PASSED_SCRIPTS * 100 / TOTAL_SCRIPTS ))%"
    echo ""
    
    echo "Individual Test Results:"
    for result in "${TEST_RESULTS[@]}"; do
        echo "  $result"
    done
    echo ""
    
    if [ $FAILED_SCRIPTS -eq 0 ]; then
        print_status "PASS" "🎉 ALL TESTS PASSED! TGW-attached Network Firewall architecture is fully functional."
        echo ""
        echo "✅ Infrastructure Configuration: VALIDATED"
        echo "✅ EC2 Connectivity: WORKING (includes Internet connectivity)"
        echo "✅ Firewall Policies: ENFORCED"
        echo ""
        echo "🚀 Your TGW-attached Network Firewall is ready for production use!"
        return 0
    else
        print_status "FAIL" "⚠️  $FAILED_SCRIPTS out of $TOTAL_SCRIPTS test scripts failed."
        echo ""
        echo "❌ Some functionality is not working as expected"
        echo "📋 Review the test outputs above for specific failures"
        echo "🔧 Consult TEST_VERIFICATION_GUIDE.md for troubleshooting"
        echo "🔄 Re-run tests after addressing issues"
        return 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -v, --verbose  Enable verbose output"
    echo "  --skip-prereq  Skip prerequisite checks"
    echo ""
    echo "This script runs all verification tests for the TGW-attached Network Firewall architecture."
    echo "Tests are executed in the recommended order for optimal validation."
    echo ""
    echo "Test Execution Order:"
    echo "  1. Infrastructure Configuration Validation"
    echo "  2. EC2 Connectivity Testing (includes Internet connectivity)"
    echo "  3. Firewall Policy Verification"
    echo ""
    echo "For detailed information about expected results, see:"
    echo "  - TEST_VERIFICATION_GUIDE.md (comprehensive troubleshooting guide)"
    echo "  - EXPECTED_TEST_RESULTS.md (expected test outputs)"
}

# Parse command line arguments
SKIP_PREREQ=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --skip-prereq)
            SKIP_PREREQ=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    echo "Starting comprehensive test suite for TGW-attached Network Firewall..."
    echo ""
    
    # Run prerequisite checks unless skipped
    if [ "$SKIP_PREREQ" = false ]; then
        check_prerequisites
    fi
    
    # Test 1: Infrastructure Configuration Validation
    run_test_script "validate_firewall_config.sh" "Infrastructure Configuration Validation"
    echo ""
    
    # Test 2: EC2 Connectivity Testing
    run_test_script "test_ec2_connectivity.sh" "EC2 Connectivity Testing"
    echo ""
    
    # Test 3: Firewall Policy Verification
    run_test_script "test_firewall_policies.sh" "Firewall Policy Verification"
    echo ""
    
    # Generate final report
    generate_final_report
}

# Execute main function
main "$@"