# Test Verification Guide for TGW-attached Network Firewall

## Overview
This document provides comprehensive testing procedures and expected results for verifying the TGW-attached Network Firewall architecture. Use this guide to validate that all components are working correctly after deployment.

## Architecture Summary
- **2 Spoke VPCs**: Connected to Transit Gateway for inter-VPC communication
- **1 Egress VPC**: Provides internet connectivity via NAT gateways
- **Transit Gateway**: Central hub for routing between VPCs
- **Network Firewall**: Attached to TGW for traffic inspection and filtering
- **EC2 Instances**: Located in private subnets of spoke VPCs with SSM connectivity

## Test Scripts Overview

### 1. test_ec2_connectivity.sh
**Purpose**: Comprehensive connectivity testing for EC2 instances
**Tests Performed**:
- SSM connectivity to all EC2 instances
- Inter-VPC connectivity between spoke VPCs through TGW
- Internet connectivity through egress VPC
- Network Firewall rule enforcement

### 2. test_firewall_policies.sh
**Purpose**: Network Firewall policy and rule verification
**Tests Performed**:
- ICMP allow rule verification
- URL blocking rule testing (www.baidu.com)
- Allowed URL access testing
- Firewall configuration validation

### 3. test_internet_connectivity.sh
**Purpose**: Specific internet connectivity validation
**Tests Performed**:
- Internet ICMP connectivity
- DNS resolution testing
- HTTP/HTTPS connectivity through firewall

### 4. validate_firewall_config.sh
**Purpose**: Configuration validation for Network Firewall
**Tests Performed**:
- Rule group configuration validation
- Firewall policy verification
- Terraform configuration validation

## Expected Test Results

### SSM Connectivity Tests
| Test | Expected Result | Failure Indicators |
|------|----------------|-------------------|
| SSM connectivity to spoke VPC 1 | ✅ PASS | Cannot connect via SSM, IAM role issues |
| SSM connectivity to spoke VPC 2 | ✅ PASS | Cannot connect via SSM, endpoint issues |

**Expected Output**:
```
[PASS] SSM connectivity working for spoke VPC 1 (i-xxxxxxxxx)
[PASS] SSM connectivity working for spoke VPC 2 (i-xxxxxxxxx)
```

### Inter-VPC Connectivity Tests
| Test | Expected Result | Failure Indicators |
|------|----------------|-------------------|
| ICMP from spoke VPC 1 to spoke VPC 2 | ✅ PASS | Ping timeout, routing issues |
| ICMP from spoke VPC 2 to spoke VPC 1 | ✅ PASS | Ping timeout, security group blocks |
| TCP connectivity (port 22) | ✅ PASS or INFO | Connection refused (expected if SSH disabled) |

**Expected Output**:
```
[PASS] ICMP connectivity works from spoke VPC 1 to spoke VPC 2 (10.93.2.x)
[PASS] ICMP connectivity works from spoke VPC 2 to spoke VPC 1 (10.93.1.x)
[INFO] TCP connectivity test result: TCP_SUCCESS (may be expected if SSH is disabled)
```

### Internet Connectivity Tests
| Test | Expected Result | Failure Indicators |
|------|----------------|-------------------|
| ICMP to 8.8.8.8 from spoke VPC 1 | ✅ PASS | Ping timeout, NAT gateway issues |
| ICMP to 8.8.8.8 from spoke VPC 2 | ✅ PASS | Ping timeout, routing issues |
| DNS resolution (www.qq.com) | ✅ PASS | DNS timeout, resolver issues |
| HTTP to allowed domain | ✅ PASS | HTTP 200/300 response codes |

**Expected Output**:
```
[PASS] Internet ICMP connectivity works from spoke VPC 1 (firewall allows ICMP)
[PASS] Internet ICMP connectivity works from spoke VPC 2 (firewall allows ICMP)
[PASS] DNS resolution works from spoke VPC 1
[PASS] HTTP request to allowed domain successful (HTTP 200)
```

### Firewall Rule Verification Tests
| Test | Expected Result | Failure Indicators |
|------|----------------|-------------------|
| ICMP allow rule (inter-VPC) | ✅ PASS | ICMP blocked between VPCs |
| ICMP allow rule (internet) | ✅ PASS | ICMP blocked to internet |
| URL blocking (www.baidu.com HTTP) | ✅ PASS | HTTP request succeeds |
| URL blocking (www.baidu.com HTTPS) | ✅ PASS | HTTPS request succeeds |
| Allowed URL access | ✅ PASS or INFO | Depends on firewall rules |

**Expected Output**:
```
[PASS] Inter-VPC ICMP connectivity works (firewall allows ICMP)
[PASS] Internet ICMP connectivity works (firewall allows ICMP)
[PASS] www.baidu.com is blocked by firewall (URL blocking rule works)
[PASS] https://www.baidu.com is blocked by firewall (TLS_SNI blocking works)
[PASS] www.qq.com is accessible (allowed URLs work)
```

### Infrastructure Verification Tests
| Test | Expected Result | Failure Indicators |
|------|----------------|-------------------|
| Transit Gateway status | ✅ PASS | TGW not available |
| VPC attachments to TGW | ✅ PASS | Missing VPC attachments |
| Network function attachment | ✅ PASS or INFO | No firewall attachment to TGW |
| Network Firewall status | ✅ PASS | Firewall not in READY state |
| Firewall policy attachment | ✅ PASS | No policy attached |
| Rule groups verification | ✅ PASS | Missing rule groups |

**Expected Output**:
```
[PASS] Transit Gateway found and available: tgw-xxxxxxxxx
[PASS] VPC attachments found on Transit Gateway
[PASS] Network function attachment found (Network Firewall attached to TGW)
[PASS] Network Firewall is in READY state
[PASS] Firewall policy is attached
[PASS] ICMP allow rule group is attached
[PASS] URL blocking rule group is attached
```

## Troubleshooting Common Issues

### SSM Connectivity Failures
**Symptoms**: Cannot connect to EC2 instances via SSM
**Possible Causes**:
- IAM instance profile not attached or incorrect policies
- SSM endpoints not configured correctly for China region
- Security groups blocking HTTPS traffic to endpoints
- VPC endpoints not in correct subnets

**Resolution Steps**:
1. Verify IAM instance profile has required SSM policies
2. Check SSM endpoint service names use `com.amazonaws.cn.{region}` format
3. Ensure security groups allow HTTPS (port 443) outbound
4. Verify VPC endpoints are in private subnets

### Inter-VPC Connectivity Failures
**Symptoms**: Cannot ping between spoke VPCs
**Possible Causes**:
- TGW route tables not configured correctly
- Security groups blocking ICMP traffic
- Route propagation not enabled
- Network ACLs blocking traffic

**Resolution Steps**:
1. Check TGW route tables have routes to both spoke VPC CIDRs
2. Verify security groups allow ICMP from parent CIDR (10.93.0.0/18)
3. Enable route propagation on TGW route tables
4. Check Network ACLs allow ICMP traffic

### Internet Connectivity Failures
**Symptoms**: Cannot reach internet from spoke VPCs
**Possible Causes**:
- NAT gateways not configured in egress VPC
- TGW routing not directing traffic to egress VPC
- Network Firewall blocking all traffic
- DNS resolution issues

**Resolution Steps**:
1. Verify NAT gateways are running in egress VPC public subnets
2. Check TGW route tables route 0.0.0.0/0 to egress VPC
3. Review Network Firewall rules for overly restrictive policies
4. Test DNS resolution separately from HTTP connectivity

### Firewall Rule Issues
**Symptoms**: Expected blocking/allowing not working
**Possible Causes**:
- Rule groups not attached to firewall policy
- Rule priorities incorrect
- Rule syntax errors
- Firewall not processing traffic

**Resolution Steps**:
1. Verify all rule groups are attached to firewall policy
2. Check rule priorities (lower numbers = higher priority)
3. Validate rule syntax in rule group definitions
4. Confirm traffic is flowing through firewall (check logs if enabled)

## Test Execution Order

### Recommended Testing Sequence
1. **Infrastructure Validation**: Run `validate_firewall_config.sh` first
2. **Basic Connectivity**: Run `test_ec2_connectivity.sh` for overall health
3. **Firewall Rules**: Run `test_firewall_policies.sh` for security validation
4. **Internet Access**: Run `test_internet_connectivity.sh` for egress validation

### Pre-Test Checklist
- [ ] AWS CLI configured with appropriate credentials
- [ ] All infrastructure deployed successfully (`terraform apply` completed)
- [ ] EC2 instances are in "running" state
- [ ] Network Firewall is in "READY" state
- [ ] Transit Gateway is in "available" state

### Post-Test Actions
- [ ] Review all test outputs for failures
- [ ] Address any failed tests using troubleshooting guide
- [ ] Document any deviations from expected results
- [ ] Re-run tests after making corrections

## Performance Expectations

### Test Execution Times
- **SSM Connectivity Tests**: 10-30 seconds per instance
- **Inter-VPC Ping Tests**: 15-30 seconds per test
- **Internet Connectivity Tests**: 30-60 seconds per test
- **Firewall Rule Tests**: 30-90 seconds per rule test
- **Infrastructure Verification**: 10-20 seconds

### Total Test Duration
- **Complete Test Suite**: 5-10 minutes
- **Individual Script**: 2-5 minutes each

## Security Considerations

### Test Impact
- All tests use read-only operations where possible
- Network tests generate minimal traffic
- No persistent changes made to infrastructure
- Tests use existing EC2 instances (no new resources created)

### Credentials Required
- EC2 read permissions for instance discovery
- SSM permissions for command execution
- Network Firewall read permissions for configuration validation
- Transit Gateway read permissions for verification

## Compliance and Validation

### Architecture Compliance
These tests validate compliance with the following requirements:
- **Requirement 6.4**: Comprehensive testing and verification
- **Requirement 4.4**: Firewall rule verification
- **Requirement 6.1-6.3**: EC2 connectivity requirements
- **Requirement 1.1-1.3**: TGW-attached firewall functionality

### Success Criteria
- All SSM connectivity tests pass
- Inter-VPC connectivity works through TGW
- Internet connectivity works through egress VPC
- Network Firewall rules are properly enforced
- Infrastructure components are in expected states

A successful test run indicates the TGW-attached Network Firewall architecture is functioning correctly and ready for production use.