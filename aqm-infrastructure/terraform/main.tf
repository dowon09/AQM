provider "aws" {
  region = var.aws_region
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

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Network
resource "aws_vpc" "aqm" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "aqm-vpc"
    Environment = "production"
  }
}

resource "aws_subnet" "aqm_public" {
  vpc_id                  = aws_vpc.aqm.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name        = "aqm-public-subnet"
    Environment = "production"
  }
}

resource "aws_internet_gateway" "aqm" {
  vpc_id = aws_vpc.aqm.id

  tags = {
    Name        = "aqm-igw"
    Environment = "production"
  }
}

resource "aws_route_table" "aqm_public" {
  vpc_id = aws_vpc.aqm.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.aqm.id
  }

  tags = {
    Name        = "aqm-public-rt"
    Environment = "production"
  }
}

resource "aws_route_table_association" "aqm_public" {
  subnet_id      = aws_subnet.aqm_public.id
  route_table_id = aws_route_table.aqm_public.id
}

# Security
resource "aws_security_group" "aqm" {
  name_prefix = "aqm-k3s-"
  description = "AQM web traffic"
  vpc_id      = aws_vpc.aqm.id

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
    description = "Outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "aqm-k3s"
    Environment = "production"
  }
}

# SSM administration; no SSH ingress is needed.
resource "aws_iam_role" "aqm_host" {
  name = "aqm-k3s-host-role"
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

  tags = {
    Environment = "production"
  }
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.aqm_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.aqm_host.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "aqm_host" {
  name = "aqm-k3s-instance-profile"
  role = aws_iam_role.aqm_host.name
}

# Persistent, encrypted application data volume.
resource "aws_ebs_volume" "aqm_data" {
  availability_zone = aws_subnet.aqm_public.availability_zone
  size              = var.data_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name        = "aqm-data"
    Environment = "production"
  }
}

resource "aws_instance" "aqm_k3s" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.aqm_public.id
  vpc_security_group_ids      = [aws_security_group.aqm.id]
  iam_instance_profile        = aws_iam_instance_profile.aqm_host.name
  associate_public_ip_address = true

  # A bootstrap change deliberately rebuilds the instance.
  user_data_replace_on_change = true

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -Eeuo pipefail
    exec > >(tee -a /var/log/aqm-bootstrap.log) 2>&1

    trap 'rc=$?; echo "ERROR: Bootstrap failed at line $LINENO (exit $rc)"; exit "$rc"' ERR

    export DEBIAN_FRONTEND=noninteractive

    echo "Updating packages..."
    apt-get -o Acquire::Retries=3 update
    apt-get -o Acquire::Retries=3 install -y \
      ca-certificates curl e2fsprogs util-linux

    # The EBS attachment can appear after user data starts.
    DEVICE="/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${replace(aws_ebs_volume.aqm_data.id, "-", "")}"

    echo "Waiting for data volume: $DEVICE"
    for attempt in $(seq 1 300); do
      udevadm settle || true
      if [ -b "$DEVICE" ]; then
        break
      fi
      sleep 2
    done

    if [ ! -b "$DEVICE" ]; then
      echo "ERROR: Data volume did not appear: $DEVICE"
      ls -l /dev/disk/by-id/ || true
      exit 1
    fi

    DEVICE="$(readlink -f "$DEVICE")"

    # Format only a genuinely blank disk.
    FS_TYPE="$(blkid -s TYPE -o value "$DEVICE" 2>/dev/null || true)"

    if [ -z "$FS_TYPE" ]; then
      if wipefs -n "$DEVICE" | grep -q .; then
        echo "ERROR: Existing disk signatures found; refusing to format"
        exit 1
      fi

      echo "Creating ext4 filesystem on blank data volume..."
      mkfs.ext4 -F "$DEVICE"
      FS_TYPE="$(blkid -s TYPE -o value "$DEVICE")"
    fi

    if [ "$FS_TYPE" != "ext4" ]; then
      echo "ERROR: Expected ext4 filesystem, found '$FS_TYPE'"
      exit 1
    fi

    DEVICE_UUID="$(blkid -s UUID -o value "$DEVICE")"
    test -n "$DEVICE_UUID"

    mkdir -p /data

    if mountpoint -q /data; then
      MOUNTED_UUID="$(findmnt -n -o UUID --target /data)"
      if [ "$MOUNTED_UUID" != "$DEVICE_UUID" ]; then
        echo "ERROR: /data is mounted from the wrong filesystem"
        exit 1
      fi
    else
      mount "UUID=$DEVICE_UUID" /data
    fi

    # Write a single persistent /data entry atomically.
    FSTAB_TMP="$(mktemp /etc/fstab.aqm.XXXXXX)"
    awk '$2 != "/data" { print }' /etc/fstab > "$FSTAB_TMP"
    printf 'UUID=%s /data ext4 defaults,nofail 0 2\n' \
      "$DEVICE_UUID" >> "$FSTAB_TMP"
    chmod 0644 "$FSTAB_TMP"
    mv "$FSTAB_TMP" /etc/fstab

    test "$(findmnt -n -o UUID --target /data)" = "$DEVICE_UUID"

    echo "Installing K3s from the stable channel..."
    curl --retry 5 --retry-delay 2 --retry-connrefused \
      -fsSL https://get.k3s.io -o /tmp/install-k3s.sh

    INSTALL_K3S_CHANNEL=stable sh /tmp/install-k3s.sh
    rm -f /tmp/install-k3s.sh

    systemctl enable --now k3s
    systemctl is-active --quiet k3s
    k3s kubectl get nodes

    echo "AQM bootstrap completed successfully"
  EOF

  tags = {
    Name        = "aqm-k3s"
    Environment = "production"
  }

  depends_on = [
    aws_iam_role_policy_attachment.ssm,
    aws_route_table_association.aqm_public
  ]
}

# This attachment is created after the instance. Bootstrap waits for the disk.
resource "aws_volume_attachment" "aqm_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.aqm_data.id
  instance_id = aws_instance.aqm_k3s.id
}

output "instance_id" {
  value = aws_instance.aqm_k3s.id
}

output "public_ip" {
  value = aws_instance.aqm_k3s.public_ip
}

output "vpc_id" {
  value = aws_vpc.aqm.id
}

output "public_subnet_id" {
  value = aws_subnet.aqm_public.id
}
