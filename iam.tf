resource "aws_iam_role" "ssm_role" {
  name                = "ssm_role"
  assume_role_policy  = data.aws_iam_policy_document.ssm_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm_role_ec2" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws-cn:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

resource "aws_iam_role_policy_attachment" "ssm_role_core" {
  role       = aws_iam_role.ssm_role.name
  policy_arn = "arn:aws-cn:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm_profile" {
  name = "spoke_ssm_profile"
  role = aws_iam_role.ssm_role.name
}
