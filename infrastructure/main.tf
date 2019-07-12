variable "name" {
  description = "Global name of this project"
}

variable "region" {
  description = "AWS region"
}

provider "aws" {
    version = "~> 2.0"
    region = "${var.region}"
}

resource "aws_ecr_repository" "api-ecr" {
  name = "${var.name}-api"
}

data "aws_ami" "api_ec2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  owners = ["amazon"] # Canonical
}

resource "aws_launch_template" "api_instance_template" {
  image_id = "${data.aws_ami.api_ec2.id}"
  name_prefix   = "${var.name}"
  instance_type = "t3.nano"
  user_data = "${base64encode(data.template_file.user_data.rendered)}"
  monitoring {
    enabled = true
  }
  
  iam_instance_profile {
    name = "${aws_iam_instance_profile.ecs_instance_profile.name}"
  }

  credit_specification {
    cpu_credits = "standard"
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}"
    }
  }
}

resource "aws_placement_group" "cluster_placement_group" {
  name = "${var.name}"
  strategy = "cluster"
}

resource "aws_autoscaling_group" "cluster_autoscale_group" {
  name_prefix = "${var.name}"
  min_size = 1
  max_size = 3
  desired_capacity = 1
  placement_group = "${aws_placement_group.cluster_placement_group.id}"
  availability_zones = ["eu-central-1c"]
  launch_template {
    id = "${aws_launch_template.api_instance_template.id}"
  }
}

resource "aws_autoscaling_policy" "cluster_autoscale_policy" {
  name = "${var.name}-autoscale-policy"
  autoscaling_group_name = "${aws_autoscaling_group.cluster_autoscale_group.name}"
  adjustment_type = "ChangeInCapacity"
  policy_type = "TargetTrackingScaling"
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 60.0
  }
}

resource "aws_ecs_cluster" "cluster" {
  name = "${var.name}-cluster"
}

resource "aws_ecs_task_definition" "api-task-definition" {
  family = "terraform-api-task-definition"
  container_definitions = "${file("task-definitions/api-service.json")}"
}

resource "aws_ecs_service" "ecs_service" {
  cluster = "${aws_ecs_cluster.cluster.id}"
  name = "terraform-prototype-api-service"
  task_definition = "${aws_ecs_task_definition.api-task-definition.arn}"
  desired_count = 1
  
}

data "template_file" "user_data" {
  template = "${file("${path.module}/templates/user-data.sh")}"
  vars = {
    cluster_name = "${aws_ecs_cluster.cluster.name}"
  }
}

resource "aws_iam_role" "instance_role" {
  name = "ec2-ecs-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs_policy" {
  role = "${aws_iam_role.instance_role.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs_instance_profile"
  role = "${aws_iam_role.instance_role.name}"
}
