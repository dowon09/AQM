variable "aws_region" {
  description = "AWS region for AQM"
  type        = string
  default     = "eu-north-1"
}

variable "instance_type" {
  description = "The EC2 instance type for the AQM K3s host."
  type        = string
  default     = "t3.small"
}

variable "data_volume_size" {
  description = "Persistent EBS volume size in GB for the EC2 instance."
  type        = number
  default     = 20
}

variable "vpc_cidr" {
  description = "CIDR range for the AQM VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR range for the AQM public subnet"
  type        = string
  default     = "10.0.1.0/24"
}
