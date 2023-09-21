# main.tf

# Configure o provedor AWS
provider "aws" {
  region = "us-east-1" 
}

# VPC
resource "aws_vpc" "kafka_vpc" {
  cidr_block = var.vpc_cidr_block
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "kafka-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "kafka_igw" {
  vpc_id = aws_vpc.kafka_vpc.id
}



# subnets privadas
resource "aws_subnet" "kafka_subnet" {
  count = var.subnet_count
  cidr_block = "10.0.${count.index * 2}.0/24"
  vpc_id = aws_vpc.kafka_vpc.id
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "kafka-subnet-${count.index + 1}"
  }
}

# rotas personalizada
resource "aws_route_table" "kafka_route_table" {
  vpc_id = aws_vpc.kafka_vpc.id
}

# rotas padrão da VPC à subnet pública
resource "aws_route_table_association" "subnet_association" {
  subnet_id      = aws_subnet.kafka_subnet[0].id
  route_table_id = aws_vpc.kafka_vpc.main_route_table_id
}


# rota para direcionar o tráfego para a Internet Gateway
resource "aws_route" "igw_route" {
  #route_table_id         = aws_route_table.kafka_route_table.id
  route_table_id         = aws_vpc.kafka_vpc.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.kafka_igw.id
}




# SG Kafka
resource "aws_security_group" "kafka_security_group" {
  name        = "kafka-security-group"
  description = "Grupo de seguranca para Kafka"
  vpc_id      = aws_vpc.kafka_vpc.id

  # Permite tráfego interno para o Kafka
  ingress {
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.kafka_vpc.cidr_block]
  }

    ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

   # Regra de entrada para ZooKeeper
  ingress {
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Regra de saída padrão (permite todo o tráfego de saída)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# função IAM para as instâncias EC2
resource "aws_iam_instance_profile" "ssm_instance_profile" {
  name = "ssm-instance-profile"
  role = aws_iam_role.ssm_role.name
}

#  IAM para o SSM
resource "aws_iam_policy" "ssm_policy" {
  name        = "ssm-policy"
  description = "Policy for SSM"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "ssm:UpdateInstanceInformation",
          "ssm:ListCommands",
          "ssm:DescribeInstanceProperties",
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
          "ssm:DescribeAssociation",
          "ssm:GetDeployablePatchSnapshotForInstance",
          "ssm:GetDocument",
          "ssm:DescribeDocument",
          "ssm:GetManifest",
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:ListAssociations",
          "ssm:ListInstanceAssociations",
          "ssm:PutInventory",
          "ssm:PutComplianceItems",
          "ssm:PutConfigurePackageResult",
          "ssm:UpdateAssociationStatus",
          "ssm:UpdateInstanceAssociationStatus",
          "ssm:UpdateInstanceInformation",
          "ssm:StartSession"
        ],
        Effect   = "Allow",
        Resource = "*",
      },
    ],
  })
}

# Anexe a política à função IAM
resource "aws_iam_role_policy_attachment" "ssm_attachment" {
  policy_arn = aws_iam_policy.ssm_policy.arn
  role       = aws_iam_role.ssm_role.name
}

# função IAM para as instâncias EC2
resource "aws_iam_role" "ssm_role" {
  name = "ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com",
        },
      },
    ],
  })
}


# Configuração da instância Kafka (
resource "aws_instance" "kafka_broker" {
  count = 1 
  ami           = var.instance_ami
  instance_type = var.instance_type
  subnet_id     = element(aws_subnet.kafka_subnet.*.id, count.index % length(aws_subnet.kafka_subnet))
  #security_groups = [aws_security_group.kafka_security_group.name]
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  key_name = "kafkalab"
  security_groups = [aws_security_group.kafka_security_group.id]
  associate_public_ip_address = true
  #count = length(keys(var.instance_ips))
  private_ip = var.instance_ips[keys(var.instance_ips)[count.index]]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              sudo yum install -y java-1.8.0
              sudo dnf install maven -y
              sudo yum install pip -y
              sudo pip install confluent-kafka
              # Instalação do SSM Agent
              sudo yum install -y amazon-ssm-agent
              # Iniciar o SSM Agent
              sudo systemctl start amazon-ssm-agent
              sudo systemctl enable amazon-ssm-agent
              mkdir -p /data/kafka_broker
              chown -R ec2-user: /data/kafka_broker
              wget https://archive.apache.org/dist/kafka/2.7.0/kafka_2.12-2.7.0.tgz
              tar -xzf kafka_2.12-2.7.0.tgz
              sudo mv kafka_2.12-2.7.0 /opt/kafka
              rm kafka_2.12-2.7.0.tgz
              chown -R ec2-user: /opt/kafka
              ## Configuração do servidor Kafka ##
              echo "advertised.listeners=PLAINTEXT://10.0.0.10:9092" >> /opt/kafka/config/server.properties
              echo "log.dirs=/data/kafka_broker" >> /opt/kafka/config/server.properties
              echo "zookeeper.connect=10.0.0.13:2181" >> /opt/kafka/config/server.properties
              echo "auto.create.topics.enable=true" >> /opt/kafka/config/server.properties
              cat <<EOL > /etc/systemd/system/kafka.service
              [Unit]
              Description=Kafka
              After=network.target
              [Service]
              Type=simple
              ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
              ExecStop=/opt/kafka/bin/kafka-server-stop.sh
              User=ec2-user
              Restart=on-failure
              Environment=JAVA_HOME=/usr/lib/jvm/jdk1.8.0
              [Install]
              WantedBy=multi-user.target
              EOL
              sudo systemctl enable kkafka.service
              sudo systemctl start kafka.service
              sleep 10
              EOF

  tags = {
    Name = "kafka-broker-1"
  }
}

# Configuração da instância Kafka-zookeeper
resource "aws_instance" "kafka_zookeeper" {
  count = 1
  ami           = var.instance_ami
  instance_type = var.instance_type
  subnet_id     = element(aws_subnet.kafka_subnet.*.id, count.index % length(aws_subnet.kafka_subnet))
  #security_groups = [aws_security_group.kafka_security_group.name]
  iam_instance_profile = aws_iam_instance_profile.ssm_instance_profile.name
  key_name = "kafkalab"
  security_groups = [aws_security_group.kafka_security_group.id]
  associate_public_ip_address = true
  #count = length(keys(var.instance_ips))
  private_ip = var.zoo_instance_ips[keys(var.zoo_instance_ips)[count.index]]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              sudo yum install -y java-1.8.0
              sudo dnf install maven -y
              sudo yum install -y telnet
              # Instalação do SSM Agent
              sudo yum install -y amazon-ssm-agent
              # Iniciar o SSM Agent
              sudo systemctl start amazon-ssm-agent
              sudo systemctl enable amazon-ssm-agent
              mkdir -p /data/zookeeper
              chown -R ec2-user: /data/zookeeper
              wget https://archive.apache.org/dist/kafka/2.7.0/kafka_2.12-2.7.0.tgz
              tar -xzf kafka_2.12-2.7.0.tgz
              sudo mv kafka_2.12-2.7.0 /opt/kafka
              rm kafka_2.12-2.7.0.tgz
              ## Configuração do servidor Kafka ##
              echo "tickTime=2000" >> /opt/kafka/config/zookeeper.properties
              echo "dataDir=/data/zookeeper" >> /opt/kafka/config/zookeeper.properties
              echo "clientPort=2181" >> /opt/kafka/config/zookeeper.properties
              cat <<EOL > /etc/systemd/system/zookeeper.service
              [Unit]
              Description=Kafka
              After=network.target
              [Service]
              Type=simple
              ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
              ExecStop=/opt/kafka/bin/zookeeper-server-stop.sh
              User=ec2-user
              Restart=on-failure
              Environment=JAVA_HOME=/usr/lib/jvm/jdk1.8.0
              [Install]
              WantedBy=multi-user.target
              EOL
              sudo systemctl enable zookeeper.service
              sudo systemctl start zookeeper.service
              sleep 20
              EOF

  tags = {
    Name = "zookeeper-1"
  }
}
