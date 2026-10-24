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

variable "ssh_cidr" {
  description = "CIDR range allowed to SSH into the EC2 instance."
  type        = string
}

