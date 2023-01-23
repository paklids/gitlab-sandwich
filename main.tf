provider "aws" {
  region  = "us-west-2"
  profile = "default"
}

locals {
  domain_name = "<your base domain name goes here>"
  gitlab_a_record_short = "<the name of your dns A record for gitlab>"
  certificate_arn = "<ARN of the ACM cert goes here>"
}

##################################################################
# Data sources to get VPC and subnets
##################################################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_eip" "gitlab" {
  #count = length(data.aws_subnets.all.ids) ## we probably don't need one eip for each AZ
  count = 1
  vpc   = true
}


data "aws_route53_zone" "selected" {
  name         = "${local.domain_name}."
  private_zone = false
}

resource "aws_route53_record" "gitlab" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${local.gitlab_a_record_short}.${data.aws_route53_zone.selected.name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.gitlab[0].public_ip]
}

module "alb_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name        = "gitlab-alb-sg"
  description = "Security group for NLB to ALB sandwich"
  vpc_id      = data.aws_vpc.default.id

  ingress_with_cidr_blocks = [
    {
      from_port   = 8888
      to_port     = 8888
      protocol    = "tcp"
      description = "User-service ports"
      cidr_blocks = "0.0.0.0/0"
    },
  ]
}

##################################################################
# Network Load Balancer with Elastic IPs attached
##################################################################
module "nlb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"
  name    = "gitlab"

  load_balancer_type = "network"

  vpc_id = data.aws_vpc.default.id

  subnet_mapping = [for i, eip in aws_eip.gitlab : { allocation_id : eip.id, subnet_id : tolist(data.aws_subnets.all.ids)[0] }]

  ## SSH and HTTP (for redirect)
  http_tcp_listeners = [
    {
      port               = 22
      protocol           = "TCP"
      target_group_index = 0
    },
    {
      port               = 80
      protocol           = "TCP"
      target_group_index = 1
    },
  ]
  https_listeners = [
    {
      port              = 443
      protocol          = "TLS"
      certificate_arn    = local.certificate_arn
      target_group_index = 2
    },
  ]

  target_groups = [
    {
      name_prefix        = "ssh-"
      backend_protocol   = "TCP"
      backend_port       = 22
      target_type        = "instance"
      preserve_client_ip = true
    },
    {
      name_prefix        = "http-"
      backend_protocol   = "TCP"
      backend_port       = 8888
      target_type        = "alb"
    },
    {
      name_prefix        = "https-"
      backend_protocol   = "TLS"
      backend_port       = 443
      target_type        = "instance"
      preserve_client_ip = true
    },
  ]
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = "gitlab"

  load_balancer_type = "application"

  vpc_id          = data.aws_vpc.default.id
  subnets         = [ data.aws_subnets.all.ids[0], data.aws_subnets.all.ids[1] ]
  security_groups = [module.alb_sg.security_group_id]

  http_tcp_listeners = [
    {
      port        = 8888
      protocol    = "HTTP"
      action_type = "redirect"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  ]
}

## NLB to ALB attach for tcp/80
resource "aws_lb_target_group_attachment" "httpattach" {
  target_group_arn = module.nlb.target_group_arns[1]
  target_id        = module.alb.lb_id
}