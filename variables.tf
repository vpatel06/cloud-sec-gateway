variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "The AWS geographic region where our infrastructure will live."

  validation {
    condition     = var.aws_region == "us-east-1"
    error_message = "To guarantee strict free-tier compliance and alignment with your environment, the region must be set to us-east-1"
  }
}

variable "environment" {
  type        = string
  default     = "sandbox"
  description = "Deployment environment tag used for tracking resource allocation."
}

variable "vpc_cidr" {
  type        = string
  default     = "10.0.0.0/16"
  description = "The base IP allocation block for our isolated virtual network framework."
}

variable "availability_zones" {
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
  description = "Isolated AWS data centers used to dynamically map out our network footprint."
}

variable "wireguard_port" {
  type        = number
  default     = 51820
  description = "UDP port used by the WireGuard VPN tunnel for client connections."
}