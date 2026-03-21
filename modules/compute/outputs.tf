output "server_public_ip" {
  value = aws_instance.server.public_ip
}

output "agent_public_ips" {
  value = aws_instance.agent[*].public_ip
}