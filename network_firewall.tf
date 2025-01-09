resource "aws_networkfirewall_rule_group" "allow_icmp" {
  capacity    = 100
  name        = "allow-icmp-rule-group"
  type        = "STATEFUL"
  description = "Rule group that allows ICMP traffic"

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = ["10.93.0.0/18"]
        }
      }
    }

    rules_source {
      stateful_rule {
        action = "PASS"
        header {
          destination      = "ANY"
          destination_port = "ANY"
          direction        = "ANY"
          protocol         = "ICMP"
          source           = "ANY"
          source_port      = "ANY"
        }
        rule_option {
          keyword = "sid:1; msg:\"Allowing ICMP traffic\""
        }
      }
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }
}

resource "aws_networkfirewall_rule_group" "block_url" {
  capacity    = 100
  name        = "block-url-rule-group"
  type        = "STATEFUL"
  description = "Rule group that blocks specific URLs"

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = ["10.93.0.0/18"]
        }
      }
    }
    
    rules_source {
      rules_source_list {
        generated_rules_type = "DENYLIST"
        target_types         = ["HTTP_HOST", "TLS_SNI"]
        targets              = ["www.baidu.com"]
      }
    }
    
    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }
}

resource "aws_networkfirewall_firewall_policy" "example_policy" {
  name = "example-firewall-policy"

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]

    stateful_engine_options {
      rule_order = "STRICT_ORDER"
    }
    
    stateful_default_actions = ["aws:alert_established"]

    stateful_rule_group_reference {
      resource_arn = "arn:aws-cn:network-firewall:cn-northwest-1:aws-managed:stateful-rulegroup/MalwareDomainsStrictOrder"
      priority     = 50
    }

    stateful_rule_group_reference {
      resource_arn = "arn:aws-cn:network-firewall:cn-northwest-1:aws-managed:stateful-rulegroup/ThreatSignaturesBotnetStrictOrder"
      priority     = 75
    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.block_url.arn
      priority     = 100
    }

    stateful_rule_group_reference {
      resource_arn = aws_networkfirewall_rule_group.allow_icmp.arn
      priority     = 200
    }
  }
}

resource "aws_networkfirewall_firewall" "inspection" {
  name                = "inspection-firewall"
  firewall_policy_arn = aws_networkfirewall_firewall_policy.example_policy.arn
  vpc_id              = aws_vpc.vpc.id
  subnet_mapping {
    subnet_id = aws_subnet.firewall_subnet[0].id
  }
  subnet_mapping {
    subnet_id = aws_subnet.firewall_subnet[1].id
  }
  tags = {
    Name = "inspection-firewall"
  }
  depends_on = [
    aws_subnet.firewall_subnet,
    aws_networkfirewall_firewall_policy.example_policy
  ]
}