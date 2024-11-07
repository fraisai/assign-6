resource "aws_lb" "app_lb" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.fariha_assign6_alb_sg.id]
  subnets            = aws_subnet.fariha_subnet_public

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


# Part 6: Application Load Balancer (ALB) with Path-Based Routing
resource "aws_lb" "app_lb" {
  name               = "app-load-balancer"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.fariha_assign6_alb_sg.id]
  subnets            = aws_subnet.public_subnets[*].id
}

resource "aws_lb_target_group" "lambda_tg" {
  name        = "lambda-target-group"
  target_type = "lambda"

  health_check {
    enabled   = true
    interval  = 30
    path      = "/api"
  }
}

# Register Lambda with the ALB Target Group
resource "aws_lambda_permission" "allow_alb" {
  statement_id  = "AllowExecutionFromALB"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api_lambda.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.lambda_tg.arn
}

# ALB Listener with Path-Based Routing for /api
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda_tg.arn
  }
}

resource "aws_lb_listener_rule" "path_based_routing" {
  listener_arn = aws_lb_listener.http_listener.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["/api"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lambda_tg.arn
  }
}

# Security Group for ALB
resource "aws_security_group" "alb_sg" {
  name        = "alb-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.main.id

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
}
