data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "aqm" {
  name_prefix = "aqm-k3s-"
  description = "AQM K3s host"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "aqm_host" {
  name_prefix = "aqm-k3s-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.aqm_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "aqm_host" {
  name = "aqm-k3s-instance-profile"
  role = aws_iam_role.aqm_host.name
}

resource "aws_ebs_volume" "aqm_data" {
  availability_zone = aws_instance.aqm_k3s.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
}

resource "aws_volume_attachment" "aqm_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.aqm_data.id
  instance_id = aws_instance.aqm_k3s.id
}

resource "aws_instance" "aqm_k3s" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                  = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.aqm.id]
  iam_instance_profile        = aws_iam_instance_profile.aqm_host.name
  associate_public_ip_address = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    apt-get update
    apt-get install -y ca-certificates curl
    mkdir -p /data
    if ! blkid /dev/sdf >/dev/null 2>&1; then mkfs.ext4 -F /dev/sdf; fi
    mount /dev/sdf /data
    echo '/dev/sdf /data ext4 defaults,nofail 0 2' >> /etc/fstab
    curl -sfL https://get.k3s.io | sh -
  EOF
}

output "instance_id" {
  value = aws_instance.aqm_k3s.id
}

output "public_ip" {
  value = aws_instance.aqm_k3s.public_ip
}
