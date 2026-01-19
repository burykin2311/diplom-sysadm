terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  cloud_id  = "b1gtnlqdkc8abnp0rqjl"
  folder_id = "b1gbem4h3ap2on2aovuh"
  zone      = "ru-central1-a"
}

# СЕТЬ
resource "yandex_vpc_network" "diploma_net" {
  name = "diploma-network"
}

# NAT-шлюз для интернета в приватной сети
resource "yandex_vpc_gateway" "nat_gateway" {
  name = "nat-gateway"
  shared_egress_gateway {}
}

resource "yandex_vpc_route_table" "private_rt" {
  network_id = yandex_vpc_network.diploma_net.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}

# ПОДСЕТИ 
resource "yandex_vpc_subnet" "public" {
  name           = "public-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.diploma_net.id
  v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_vpc_subnet" "private" {
  name           = "private-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.diploma_net.id
  v4_cidr_blocks = ["192.168.20.0/24"]
  route_table_id = yandex_vpc_route_table.private_rt.id
}

# Источник образа (ubuntu)
data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2204-lts"
}

# ВИРТУАЛЬНЫЕ МАШИНЫ 

# 1. bastion
resource "yandex_compute_instance" "bastion" {
  name        = "bastion"
  platform_id = "standard-v3"
  scheduling_policy { preemptible = true }
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.public.id
    nat       = true
  }
  metadata = {
    user-data = "${file("./meta.yaml")}"
  }
}

# 2. Веб-сервер
resource "yandex_compute_instance" "web1" {
  name        = "web1"
  platform_id = "standard-v3"
  scheduling_policy { preemptible = true }
  resources {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.private.id
    nat       = false
  }
  metadata = {
    user-data = "${file("./meta.yaml")}"
  }
}

# 3. Zabbix Server
resource "yandex_compute_instance" "zabbix" {
  name        = "zabbix"
  platform_id = "standard-v3"
  scheduling_policy { preemptible = true }
  resources {
    cores         = 2
    memory        = 4
    core_fraction = 20
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 15
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.public.id
    nat       = true
  }
  metadata = {
    user-data = "${file("./meta.yaml")}"
  }
}

# ОТКАЗОУСТОЙЧИВОСТЬ 
resource "yandex_compute_snapshot_schedule" "default" {
  name = "every-day-snapshot"
  schedule_policy {
    expression = "0 0 * * *"
  }
  snapshot_spec {
    description = "Daily backup"
    labels      = { project = "diploma" }
  }
  retention_period = "168h"
  disk_ids = [
    yandex_compute_instance.bastion.boot_disk[0].disk_id,
    yandex_compute_instance.web1.boot_disk[0].disk_id,
    yandex_compute_instance.zabbix.boot_disk[0].disk_id
  ]
}

# 4. Elasticsearch + Kibana 
resource "yandex_compute_instance" "logging" {
  name        = "logging"
  platform_id = "standard-v3"
  scheduling_policy { preemptible = true }
  resources {
    cores         = 2
    memory        = 4
    core_fraction = 20
  }
  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 15
    }
  }
  network_interface {
    subnet_id = yandex_vpc_subnet.public.id
    nat       = true
  }
  metadata = {
    user-data = "${file("./meta.yaml")}"
  }
}
