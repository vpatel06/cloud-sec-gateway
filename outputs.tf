output "instance_id" {
  value       = aws_instance.secure_gateway.id
  description = "Use with: aws ssm start-session --target <id>"
}

output "instance_public_ip" {
  value       = aws_instance.secure_gateway.public_ip
  description = "Use this on your VPN client to connect to WireGuard"
}

output "vpc_id" {
  value = aws_vpc.vanij_vpc.id
}