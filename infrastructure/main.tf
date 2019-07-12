variable "name" {
  description = "Global name of this project"
}

provider "aws" {
    version = "~> 2.0"
    region = "eu-central-1"
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

resource "aws_instance" "web" {
  ami = "${data.aws_ami.api_ec2.id}"
  instance_type = "t3.nano"
  user_data = "${data.template_file.user_data.rendered}"
  iam_instance_profile = "${aws_iam_instance_profile.ecs_instance_profile.id}"

  tags = {
    Name = "${var.name}"
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


# resource "aws_launch_configuration" "api_config" {
#   image_id = "${data.aws_ami.ubuntu.id}"
#   name_prefix   = "terraform-lc-example-"
#   instance_type = "t3.nano"
#   user_data = "${data.template_file.user_data.rendered}"
  
#   lifecycle {
#     create_before_destroy = true
#   }
# }

