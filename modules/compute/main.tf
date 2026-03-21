resource "aws_instance" "server" {
  ami                    = "ami-0c421724a94bba6d6"
  instance_type          = "t3.medium"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name

  user_data = <<-EOF
  #!/bin/bash
  curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true sh -
  aws s3 cp /var/lib/rancher/k3s/server/node-token s3://your-bucket/k3s-token
EOF

  tags = {
    Name = "${var.project_name}-server"
  }
}

resource "aws_instance" "agent" {
  count                  = 1
  ami                    = "ami-0c421724a94bba6d6"
  instance_type          = "t3.micro"
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.security_group_id]
  key_name               = var.key_name

  user_data = <<-EOF
  #!/bin/bash
  SERVER_IP=${aws_instance.server.private_ip}
  
  # 等待 server 的 K3s API 端口开放
  until curl -sk https://$SERVER_IP:6443 > /dev/null 2>&1; do
    echo "Waiting for K3s server..."
    sleep 10
  done
  
  # 从 server 获取 token
  TTOKEN=$(aws s3 cp s3://your-bucket/k3s-token -) \
    "sudo cat /var/lib/rancher/k3s/server/node-token")
  
  # 加入集群
  curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_SELINUX_RPM=true \
    K3S_URL=https://$SERVER_IP:6443 \
    K3S_TOKEN=$TOKEN sh -
EOF

  tags = {
    Name = "${var.project_name}-agent-${count.index}"
  }
}
