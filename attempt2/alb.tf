resource "aws_lb" "app_lb" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.fariha_assign6_alb_sg.id]
  subnets            = ["subnet-abc123", "subnet-def456"]

  enable_deletion_protection = true
}

# Security Group for Load Balancer 
resource "aws_security_group" "fariha_assign6_alb_sg" {
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.fariha_vpc_assign6.id
}
