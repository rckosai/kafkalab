# Variáveis para a VPC
variable "vpc_cidr_block" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_count" {
  description = "Número de subnets a serem criadas"
  type        = number
  default     = 1
}

# Variáveis para as instâncias EC2
variable "instance_ami" {
  description = "AMI para as instâncias EC2"
  type        = string
  default     = "ami-04cb4ca688797756f"
}

variable "instance_type" {
  description = "Tipo de instância EC2"
  type        = string
  default     = "t2.small"
}

# Variáveis para o Kafka
variable "kafka_version" {
  description = "Versão do Kafka"
  type        = string
  default     = "2.7.0"
}

# Variáveis para o ZooKeeper
variable "zookeeper_version" {
  description = "Versão do ZooKeeper"
  type        = string
  default     = "3.7.1"
}

variable "instance_ips" {
  type = map(string)
  default = {
    "kafka-broker-1" = "10.0.0.10"
    "kafka-broker-2" = "10.0.0.11"
    "kafka-broker-3" = "10.0.0.12"
  }
}

variable "zoo_instance_ips" {
  type = map(string)
  default = {
    "zookeeper-1" = "10.0.0.13"
    "zookeeper-2" = "10.0.0.14"
    "zookeeper-3" = "10.0.0.15"
  }
}