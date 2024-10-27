
# Create VPC 
data "aws_availability_zones" "available" {
    state                   = "available"
}


resource "aws_vpc" "fariha_vpc_assign6" {
    cidr_block = var.vpc_cidr
    enable_dns_hostnames = true
    enable_dns_support   = true

    tags = {
        Name = "fariha-vpc-assign6"
    }
}

# Create & attach IGW to VPC
resource "aws_internet_gateway" "fariha_assign6_igw" {
    vpc_id = aws_vpc.fariha_vpc_assign6.id # attach igw to vpc
    tags = {
        Name = "fariha-igw-assign6"
    }
}

# Create 2 public subnets in VPC
resource "aws_subnet" "fariha_subnet_public" {
    count = var.subnet_count.public
    vpc_id = aws_vpc.fariha_vpc_assign6.id
    cidr_block = var.subnet_public_cidr[count.index]
    availability_zone = data.aws_availability_zones.available.names[count.index]
    tags = {
        Name = "fariha_public_${count.index}"
    }
}

# Create 2 private subnets in VPC
resource "aws_subnet" "fariha_subnet_private" {
    count = var.subnet_count.private
    vpc_id = aws_vpc.fariha_vpc_assign6.id
    cidr_block = var.subnet_private_cidr[count.index]
    availability_zone = data.aws_availability_zones.available.names[count.index]
    tags = {
        Name = "fariha_private_${count.index}"
    }
}

# Create 1 NAT Gateway per AZ
resource "aws_nat_gateway" "assign6_nat" {
    depends_on = [aws_internet_gateway.fariha_assign6_igw]
    count = var.subnet_count.public
    subnet_id = aws_subnet.fariha_subnet_public[count.index].id
    allocation_id = var.allocate_id
}


# Create Public Route table (public subnets)
resource "aws_route_table" "assign6_public_rt" {
    vpc_id = aws_vpc.fariha_vpc_assign6.id
    
    # to give access to the internet, add destination of 0.0.0.0/0 and target the igw I created earlier
    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.fariha_assign6_igw.id
    }
}

# add the public subnets to the public route table 
resource "aws_route_table_association" "public" {
    count = var.subnet_count.public
    route_table_id = aws_route_table.assign6_public_rt.id
    subnet_id = aws_subnet.fariha_subnet_public[count.index].id
}


# Create Private Route table (private subnets)
resource "aws_route_table" "assign6_private_rt" {
    vpc_id = aws_vpc.fariha_vpc_assign6.id
    count = var.subnet_count.private

    # sends all other subnet traffic to the NAT gateway, add destination of 0.0.0.0/0 and target the nat-gateway I created earlier
    route {
        cidr_block              = "0.0.0.0/0"
        nat_gateway_id          = aws_nat_gateway.assign6_nat[count.index].id
    }
}

# add the private subnets to the private route table 
resource "aws_route_table_association" "private" {
    count = var.subnet_count.private
    route_table_id = aws_route_table.assign6_private_rt[count.index].id
    subnet_id = aws_subnet.fariha_subnet_private[count.index].id
}


/***************************
 * PART 1: ADVANCED AUTO SCALING AND HIGH AVAILABILITY
 ***************************/

/***************************
 * 1.1: LAUNCH TEMPLATE
    - Create a Launch Template for your EC2 instances using Amazon Linux 2.
    - Ensure IAM roles are attached to allow instances to interact with other AWS services (S3, CloudWatch, etc.).
 ***************************/


# Define AMI for instance
data "aws_ami" "amazon-linux" {
  most_recent = true
  owners      = ["amazon"]
}

# Security Group for ASG EC2 instances
 # Allows ingress HTTP traffic on port 80 and all outbound traffic. However, it restricts inbound traffic to requests coming from any source associated with the ALB security group, ensuring that only requests forwarded from my load balancer will reach your instances.
resource "aws_security_group" "fariha_assign_instance" {
    ingress {
        from_port       = 80
        to_port         = 80
        protocol        = "tcp"
        security_groups = [aws_security_group.fariha_assign6_alb_sg.id]
    }

    egress {
        from_port       = 0
        to_port         = 0
        protocol        = "-1"
        cidr_blocks     = ["0.0.0.0/0"]
    }

    vpc_id = aws_vpc.fariha_vpc_assign6.id
}


# Configure launch template (to specify the EC2 instance configuration that an ASG will use to launch each new instance)
resource "aws_launch_template" "fariha_assign6_lt" {
    name_prefix            = "fariha-assign6-lt"
        # name prefix to use for all versions of this launch configuration - Terraform will append a unique identifier to the prefix for each launch configuration created

    image_id        = data.aws_ami.amazon-linux.id
        # Amazon Linux AMI specified by a data source (data source from line 23)

    instance_type = "t3.micro"
        # instance type

    user_data       = filebase64("${path.module}/user-data.sh")
        # user data script - configures the instances to run the user-data.sh file in this repository at launch time

    vpc_security_group_ids = ["${aws_security_group.fariha_assign_instance.id}"]
        # allows ingress traffic on port 80 and egress traffic to all endpoints

    block_device_mappings { # attach EBS Volume
        device_name = "/dev/sdh" 
        ebs {
            volume_type    = "gp3"
        }
    }

    lifecycle { # lifecycle block = use to avoid unwanted scaling of your ASG
        create_before_destroy = true
            # Why use lifecyle block?
                # bc you cannot modify a launch configuration, so any changes to the definition force Terraform to create a new resource. create_before_destroy argument in the lifecycle block instructs Terraform to create the new version before destroying the original to avoid any service interruptions
                # use Terraform lifecycle arguments to avoid drift or accidental changes - since ASGs are dynamic and Terraform does not manage the underlying instances directly because every scaling action would introduce state drift. 
    }
}


/***************************
 * 1.4: AUTO HEALING
    - Configure EC2 Auto Recovery to automatically replace unhealthy instances using a health check based on EC2 status checks and ELB health checks. 
 ***************************/

# ASG configuration
resource "aws_autoscaling_group" "fariha_assign6_asg" {
    name = "fariha_assign6_asg"
    min_size             = 2
    max_size             = 3
    desired_capacity     = 2
    
    launch_template { # Launch Template
        id      = aws_launch_template.fariha_assign6_lt.id
        version = "$Latest"
    }
    count = var.subnet_count.public
    vpc_zone_identifier  = [aws_subnet.fariha_subnet_public[count.index].id]
        # the subnets where the ASGs will launch new instances

    health_check_type    = "both" # performs ELB & EC2 instance check - 1.4

    tag {
        key                 = "Name"
        value               = "fariha_tf"
        propagate_at_launch = true
    }
}


/***************************
 * 1.2: ASG with DYNAMIC SCALING
    - Configure an Auto Scaling Group (ASG) to launch EC2 instances across multiple Availability Zones.
    - Set dynamic scaling policies based on CPU utilization, RAM, and network throughput.
    - Implement a predictive scaling policy based on historical usage patterns to proactively adjust the number of instances.
 ***************************/

resource "aws_autoscaling_policy" "fariha_asg_policy" {
    autoscaling_group_name = "fariha_assign6_asg"
    name = "predictive-policy"
    policy_type            = "PredictiveScaling"
    predictive_scaling_configuration {
        metric_specification {
        target_value = 10
        customized_load_metric_specification {
            metric_data_queries {
            id         = "load_sum"
            expression = "SUM(SEARCH('{AWS/EC2,AutoScalingGroupName} MetricName=\"CPUUtilization\" fariha_assign6_asg', 'Sum', 3600))"
            }
        }
        }
    }
}

/***************************
 * 1.3: MULTI-TIER APPLICATION DEPLOYMENT
    - Set up one tier for web servers and use a placement group for web tier instances for enhanced network performance. 
    - Set up another tier for the database layer
 ***************************/
resource "aws_placement_group" "web_pg" {
  name     = "fariha-pg-web"
  strategy = "cluster"
}

resource "aws_placement_group" "db_pg" {
  name     = "fariha-pg-db"
  strategy = "cluster"
}




/***************************
 * PART 2: ELB & ENHANCED TRAFFIC MANAGEMENT
 ***************************/

/***************************
 * 2.1: ALB SETUP & SSL/TLS TERMINATION
    - Create an ALB in front of your ASG.
    - Configure SSL/TLS termination for secure connections using an ACM SSL certificate 

    Notes: 
    * You can use SSL/TLS certificates to establish secure connections which enable HTTPS for your app
    * AWS Certificate Manager (ACM) simplifies the process of provisioning, managing, and deploying these certificates (ACM handles certificate renewal)
    * To further enhance security, DNS validation can be used as a method to confirm domain ownership when issuing certificates. DNS validation involves adding a specific DNS record to your domain's configuration, which ACM then verifies. This approach is particularly useful for automating the validation process, as it avoids the need for manual intervention.

 ***************************/

/***************************
 * ALB SETUP
 ***************************/

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

# Create an application load balancer
resource "aws_lb" "assign6_alb" {
  name               = "fariha-assign6-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.fariha_assign6_alb_sg.id]
  subnets            = aws_subnet.fariha_subnet_public
}

# Specify how to handle any HTTP requests to port 80 = aka forward all requests to the load balancer to a target group. 
/***************************
  * resource "aws_lb_listener" "alb_listener" {
    load_balancer_arn = aws_lb.assign6_alb.arn
    port              = "80"
    protocol          = "HTTP"

    default_action {
      type             = "forward"
      target_group_arn = aws_lb_target_group.ec2_lb_tg.arn
    }
  }
 ***************************/


# forward all HTTP requests to the load balancer to HTTPS
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.assign6_alb.arn
  port              = "80"
  protocol          = "HTTP"

  # Redirect HTTP to HTTPS
  default_action {
    type = "redirect"
    redirect {
      host        = "#{host}"
      path        = "/"
      port        = "443"
      protocol    = "HTTPS"
      query       = "#{query}"
      status_code = "HTTP_301"
    }
  }
}

# Create HTTPS Listener
resource "aws_lb_listener" "https_listener" {
  load_balancer_arn = aws_lb.assign6_alb.arn
  port = 443
  protocol = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-11"  # ADJUST
  certificate_arn = aws_acm_certificate.fariha_acm.arn

  # Rules for path based routing - forward
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2_lb_tg.arn
  }
}

# Path-Based routing for /api to Lambda target group
resource "aws_lb_listener_rule" "api_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority = 100

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }

  action {
    type = "forward" 
    target_group_arn = aws_lb_target_group.lambda_tg.arn
  }
}

# Path-based routing for /app to EC2 target group
resource "aws_lb_listener_rule" "app_rule" {
  listener_arn = aws_lb_listener.https_listener.arn
  priority     = 200 # Lower priority than the /api rule

  condition {
    path_pattern {
      values = ["/app/*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2_lb_tg.arn
  }
}



# Target group configuration - defines the collection of instances our ALB will send traffic to (TF does not manage the configuration of the targets in that group directly, but instead specifies a list of destinations the load balancer can forward requests to).
resource "aws_lb_target_group" "ec2_lb_tg" {
  name     = "fariha-alb-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.fariha_vpc_assign6.id


  # Enable sticky sessions
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # Set the session duration in seconds (1 day here)
  }

  # Advanced health check configuration
  health_check {
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 10
    path                = "/health"       # Specify your health check endpoint
    matcher             = "200-299"       # Only accept response codes in this range
  }
}

# Target Group for Lambda function
resource "aws_lb_target_group" "lambda_tg" {
  name = "fariha-lambda-tg"
  port = 80
  protocol = "HTTP"
  vpc_id = aws_vpc.fariha_vpc_assign6.id
}


# aws_autoscaling_attachment resource links your ASG with the target group - allows AWS to automatically add/remove instances from the target group over their lifecycle.
resource "aws_autoscaling_attachment" "asg_attach" {
    for_each = toset([aws_autoscaling_group.fariha_assign6_asg])
    autoscaling_group_name = each.key
    lb_target_group_arn    = aws_lb_target_group.ec2_lb_tg.arn
}




/***************************
 * SSL/TLS TERMINATION
 ***************************/
# Request an SSL/TLS certificate and specify the domain name that you want to certify
resource "aws_acm_certificate" "fariha_acm" {
    domain_name                 = var.aditya_domain
    subject_alternative_names   = ["*.${var.aditya_domain}"]  
    validation_method           = "DNS"

    lifecycle {
        create_before_destroy   = true
    }
}

# Ensure that I have a Route53 hosted zone for my domain
data "aws_route53_zone" "selected_zone" {
    name                        = var.aditya_domain
    private_zone                = false
}

# validate the certificate via DNS - creates the necessary DNS record that AWS will check to verify domain ownership
resource "aws_route53_record" "cert_validation_record" {
    for_each = {
        for dvo in aws_acm_certificate.fariha_acm.domain_validation_options : dvo.domain_name => {
            name   = dvo.resource_record_name
            record = dvo.resource_record_value
            type   = dvo.resource_record_type
        }
    }

    allow_overwrite = true
    name            = each.value.name
    records         = [each.value.record]
    ttl             = 60
    type            = each.value.type
    zone_id         = data.aws_route53_zone.selected_zone.zone_id
}

# Wait for the validation to complete bc once the DNS records are in place, ACM will automatically check the DNS entries 
resource "aws_acm_certificate_validation" "cert_validation" {
    timeouts {
        create = "5m"
    }

    certificate_arn = aws_acm_certificate.fariha_acm.arn

    # List of FQDNs that implement the validation
    validation_record_fqdns = [for record in aws_route53_record.cert_validation_record : record.fqdn]
}



/***************************
 * PART 3: ADVANCED STORAGE SOLUTIONS & MANAGEMENT
 ***************************/

/***************************
 * 3.1: EBS & DATA REPLICATION = look at aws launch template in block_device_mappings
    - Use Provisioned IOPS EBS volumes for the database layer
    - Use GP3 volumes for the web servers.
    - Implement EBS Snapshots for regular backups and integrate with AWS Backup for automated backup policies
 ***************************/


/***************************
 * 3.2: S3 as OBJECT STORAGE FOR APPLICATION DATA
 ***************************/


/***************************
 * 3.2.1: S3 STORAGE CLASSES & LIFECYCLE POLICIES
    - Create an S3 bucket to store user files & static content
    - Implement S3 Storage Classes (e.g., Standard, Intelligent Tiering, Glacier) 
    - Design a lifecycle policy that transitions data to cost-effective storage tiers based on data access patterns
 ***************************/
# S3 Bucket
resource "aws_s3_bucket" "fariha_assign6_bucket" {
    bucket = "fariha_assign6_bucket"
    tags = {
        Name        = "fariha-assign6"
    }
}




/***************************
 * 3.2.2: S3 VERSIONING & ENCRYPTION
    - Enable versioning for bucket to preserve data integrity
    - Enforce SSE-S3 or SSE-KMS encryption for all objects stored in the bucket
 ***************************/
# Implement a lifecycle policy for the S3 bucket
resource "aws_s3_bucket_lifecycle_configuration" "fariha_lifecycle" {
  bucket = aws_s3_bucket.fariha_assign6_bucket.bucket

  # Transition policy for Standard storage class (default)
  rule {
    id     = "Standard-to-IntelligentTiering"
    status = "Enabled"

    filter {
      prefix = ""  # Apply to all objects
    }

    transition {
      days          = 30
      storage_class = "INTELLIGENT_TIERING"  # Transition to Intelligent Tiering after 30 days
    }

    expiration {
      days = 3650  # Objects expire after 10 years
    }
  }

  # Transition policy from Intelligent-Tiering to Glacier
  rule {
    id     = "IntelligentTiering-to-Glacier"
    status = "Enabled"

    filter {
      prefix = ""  # Apply to all objects
    }

    transition {
      days          = 90
      storage_class = "GLACIER"  # Transition to Glacier after 90 days
    }
  }

  # Transition from Glacier to Expiration (after 365 days in Glacier)
  rule {
    id     = "Glacier-to-Expiration"
    status = "Enabled"

    filter {
      prefix = ""  # Apply to all objects
    }

    expiration {
      days = 455  # Expire objects 455 days after creation (90 days in Intelligent Tiering + 365 days in Glacier)
    }
  }
}

# S3 Bucket Versioning
resource "aws_s3_bucket_versioning" "s3_versioning" {
  bucket = aws_s3_bucket.fariha_assign6_bucket.bucket

  versioning_configuration {
    status = "Enabled"  # Enable versioning for better data management
  }
}

# S3 Bucket Server-Side Encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "s3_encryption" {
  bucket = aws_s3_bucket.fariha_assign6_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # Default server-side encryption (AES-256)
    }
  }
}

/***************************
 * 3.3: REPLICATION & STATIC WEBSITE HOSTING
    - CRR: Set up cross-region replication for S3 buckets across 2 different regions to ensure disaster recovery
    - STATIC WEBSITE HOSTING: Host a static version of your application's frontend on S3 
 ***************************/

provider "aws" {
  alias  = "destination"
  region = "us-west-2"  # Destination bucket region
}

# Create destination S3 bucket in region us-west-2
resource "aws_s3_bucket" "destination_bucket" {
  provider = aws.destination
  bucket   = "fariha-destination-bucket-assign6"

  tags = {
    Name        = "fariha-assign6"
  }
}

# Create an IAM role for S3 replication
resource "aws_iam_role" "replication_role" {
  name = "fariha-s3-replication-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "s3.amazonaws.com"
        }
      }
    ]
  })
}

# Attach a policy to allow replication between the source and destination buckets
resource "aws_iam_role_policy" "replication_policy" {
  role = aws_iam_role.replication_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "s3:GetObjectVersionForReplication",
          "s3:GetObjectVersionAcl",
          "s3:GetObjectVersionTagging",
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags"
        ],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.fariha_assign6_bucket.arn}/*"
      },
      {
        Action = "s3:ListBucket",
        Effect = "Allow",
        Resource = aws_s3_bucket.fariha_assign6_bucket.arn
      },
      {
        Action = "s3:PutObject",
        Effect = "Allow",
        Resource = "${aws_s3_bucket.destination_bucket.arn}/*"
      }
    ]
  })
}

# Create replication configuration in the source bucket
resource "aws_s3_bucket_replication_configuration" "source_replication" {
  bucket = aws_s3_bucket.fariha_assign6_bucket.id

  role = aws_iam_role.replication_role.arn

  rule {
    id     = "ReplicationRule"
    status = "Enabled"

    filter {
      prefix = ""  # Apply to all objects
    }

    destination {
      bucket        = aws_s3_bucket.destination_bucket.arn
      storage_class = "STANDARD"  # You can use different storage classes such as STANDARD, INTELLIGENT_TIERING, etc.
    }
  }
}

# Destination bucket policy to allow replication
resource "aws_s3_bucket_policy" "destination_policy" {
  provider = aws.destination
  bucket   = aws_s3_bucket.destination_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          AWS = aws_iam_role.replication_role.arn
        },
        Action    = "s3:PutObject",
        Resource  = "${aws_s3_bucket.destination_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}


/***************************
 * PART 4: GLOBAL CONTENT DELIVERY with CLOUDFRONT
 ***************************/


/***************************
 * 4.1: CLOUDFRONT DISTRIBUTION SETUP
    - Create a CloudFront Distribution with your S3 bucket from Part 3 as the origin 
    - Set up custom cache invalidation to automatically clear cached objects during deployments
    - Implement geo-restrictions to control access based on user location
 ***************************/

# IAM Role for CloudFront to access the S3 bucket
resource "aws_iam_role" "cloudfront_access_role" {
  name = "cloudfront-access-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }]
  })
}

# Attach policy to allow CloudFront to read S3 objects
resource "aws_iam_role_policy" "cloudfront_access_policy" {
  name   = "cloudfront-access-policy"
  role   = aws_iam_role.cloudfront_access_role.id

  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "s3:GetObject"
        ],
        "Resource": [
          "${aws_s3_bucket.fariha_assign6_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Define CloudFront Distribution
resource "aws_cloudfront_distribution" "cdn_distribution" {
  origin {
    domain_name = aws_s3_bucket.fariha_assign6_bucket.bucket_regional_domain_name
    origin_id   = "s3-origin"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  default_root_object = "index.html"

  # Custom cache behavior
  default_cache_behavior {
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]

    # Set cache policy to manage cache invalidation
    cache_policy_id = aws_cloudfront_cache_policy.custom_cache_policy.id

    forwarded_values {
      query_string = true
      headers      = ["Origin"]
      cookies {
        forward = "none"
      }

    }

    # Custom TTL settings
    min_ttl                = 0
    default_ttl            = 86400  # 1 day in seconds
    max_ttl                = 31536000  # 1 year in seconds
  }

  # Geo-restrictions for content access
  restrictions {
    geo_restriction {
      restriction_type = "whitelist"  # or "blacklist" to restrict access to specific countries
      locations        = ["US", "CA", "GB"]  # Example: Allow access only to these countries
    }
  }

  # Price class for low-latency delivery
  price_class = "PriceClass_All"  # Use all edge locations globally

  # Logging (optional)
  logging_config {
    bucket = "my-logging-bucket.s3.amazonaws.com"  # Set up a logging bucket if required
  }

  # SSL configuration for HTTPS delivery
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# Origin Access Identity (OAI) to grant CloudFront access to private S3 objects
resource "aws_cloudfront_origin_access_identity" "origin_identity" {
  comment = "OAI for S3 bucket"
}

# Custom Cache Policy for Cache Invalidation
resource "aws_cloudfront_cache_policy" "custom_cache_policy" {
  name    = "custom-cache-policy"
  comment = "Custom cache policy for deployment invalidation"

  default_ttl = 86400  # 1 day
  min_ttl     = 0
  max_ttl     = 31536000  # 1 year

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Origin"]
      }
    }

    cookies_config {
      cookie_behavior = "all"
    }

    query_strings_config {
      query_string_behavior = "all"
    }
  }
}



/***************************
 * PART 5: DNS MANAGEMENT with ROUTE53
 ***************************/

/***************************
 * 5.1: ROUTE53 DNS CONFIGURATION
    - Register a domain using Route 53 and create a hosted zone.
    - Configure Weighted Routing to direct 80% of traffic to the primary region and 20% to a backup region.
    - Set up Failover Routing to handle regional outages by failing over to the secondary region automatically.
 ***************************/


/***************************
 * PART 6: SERVERLESS API & EVENT-DRIVEN ARCHITECTURE
 ***************************/

/***************************
 * 6.1: 
    - 
 ***************************/

# Create a Lambda Function
resource "aws_lambda_function" "api_handler" {
  function_name = "apiHandler"
  runtime       = "nodejs20.x" # or your preferred runtime
  handler       = "index.handler" # Assuming your handler is in index.js

  # Replace with your code or point to a ZIP file
  s3_bucket = "your-s3-bucket" # S3 bucket for your Lambda code
  s3_key    = "lambda/api_handler.zip" # S3 key for your Lambda code

  environment {
    variables = {
      DYNAMODB_TABLE = aws_dynamodb_table.users.name
    }
  }

  role = aws_iam_role.lambda_exec.arn
}

# IAM Role for Lambda Execution
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Effect    = "Allow"
      Sid       = ""
    }]
  })
}

# Attach Permissions to Lambda Role
resource "aws_iam_policy_attachment" "lambda_dynamodb" {
  name       = "lambda_dynamodb"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaDynamoDBExecutionRole"
  roles      = [aws_iam_role.lambda_exec.name]
}

# Create a Cognito User Pool
resource "aws_cognito_user_pool" "user_pool" {
  name = "user_pool"

  lambda_config {
    pre_sign_up = aws_lambda_function.api_handler.arn
  }

  username_attributes = ["email"]

  verification_message_template {
    default_email_option = "CONFIRM_WITH_LINK"
    email_message        = "Click the link to confirm your email: {####}"
    email_subject        = "Verify your email address"
  }
}

# Create a Cognito User Pool Client
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name         = "user_pool_client"
  user_pool_id = aws_cognito_user_pool.user_pool.id
  generate_secret = false
}

# Create an API Gateway
resource "aws_api_gateway_rest_api" "api" {
  name        = "my_api"
  description = "My API Gateway"
}

# Create a Resource for the API
resource "aws_api_gateway_resource" "users" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = aws_api_gateway_rest_api.api.root_resource_id
  path_part   = "users"
}

# Create a Method for the Resource
resource "aws_api_gateway_method" "post_user" {
  rest_api_id   = aws_api_gateway_rest_api.api.id
  resource_id   = aws_api_gateway_resource.users.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"

  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

# Create an API Gateway Authorizer for Cognito
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name               = "cognito_authorizer"
  rest_api_id       = aws_api_gateway_rest_api.api.id
  authorizer_uri    = "arn:aws:apigateway:${var.region}:cognito-idp:/${aws_cognito_user_pool.user_pool.id}/authorizer"
  identity_source    = "method.request.header.Authorization"
  provider_arns      = [aws_cognito_user_pool.user_pool.arn]
  type               = "COGNITO_USER_POOLS"
}

# Create a Lambda Integration
resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  resource_id = aws_api_gateway_resource.users.id
  http_method = aws_api_gateway_method.post_user.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_handler.invoke_arn
}

# Deploy the API
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [aws_api_gateway_integration.lambda_integration]
  rest_api_id = aws_api_gateway_rest_api.api.id
  stage_name  = "prod" # Change as needed
}

# Outputs
output "api_url" {
  value = "${aws_api_gateway_deployment.api_deployment.invoke_url}/users"
}

output "user_pool_id" {
  value = aws_cognito_user_pool.user_pool.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.user_pool_client.id
}

 
/***************************
 * 6.2: 
    - 
 ***************************/


/***************************
 * 6.3: 
    - 
 ***************************/

/***************************
 * PART 7: NOTIFICATION & MESSAGING SYSTEM
 ***************************/

/***************************
 * 7.1: 
    - 
 ***************************/
# Create SNS Topic for Alerts
resource "aws_sns_topic" "upload_complete_topic" {
  name = "fariha-complete-topic"
}

# Create SQS Queue to subscribe to SNS Topic
resource "aws_sqs_queue" "uploads_sqs_queue" {
  name = "fariha-completed-queue"
}

# Subscribe SQS Queue to SNS Topic
resource "aws_sns_topic_subscription" "sqs_subscription" {
  topic_arn = aws_sns_topic.upload_complete_topic.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.uploads_sqs_queue.arn

  # Allow SNS to send messages to SQS
  depends_on = [aws_sqs_queue_policy.sqs_policy]
}

# SNS Policy to Allow SNS to Publish to SQS
resource "aws_sqs_queue_policy" "sqs_policy" {
  queue_url = aws_sqs_queue.uploads_sqs_queue.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "sns.amazonaws.com"
        },
        Action = "sqs:SendMessage",
        Resource = aws_sqs_queue.uploads_sqs_queue.arn,
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.upload_complete_topic.arn
          }
        }
      }
    ]
  })
}


# Subscribe Email to SNS Topic
resource "aws_sns_topic_subscription" "email_subscription" {
  topic_arn = aws_sns_topic.upload_complete_topic.arn
  protocol  = "email"
  endpoint  = "Fariha.Iftekher.tc@techconsulting.tech"
}

/***************************
 * 7.2: 
    - 
 ***************************/

# Create Lambda Function to process uploads and publish to SNS
resource "aws_lambda_function" "process_uploads_lambda" {
  filename         = "lambda_function.zip"  # Path to your Lambda deployment package
  function_name    = "process_uploads_function"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs14.x"  # Example with Node.js
  source_code_hash = filebase64sha256("lambda_function.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN = aws_sns_topic.upload_complete_topic.arn
    }
  }

  tags = {
    Name = "ProcessUploadsLambda"
  }
}

# Add Lambda Permission to S3 Bucket for Invocation
resource "aws_lambda_permission" "s3_invoke_lambda" {
  statement_id  = "AllowS3Invocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.process_uploads_lambda.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.fariha_assign6_bucket.arn
}

# S3 Bucket Notification for Lambda Invocation on Object Creation
resource "aws_s3_bucket_notification" "s3_to_lambda" {
  bucket = aws_s3_bucket.fariha_assign6_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.process_uploads_lambda.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke_lambda]
}

# Create Lambda to Subscribe to SNS Topic
resource "aws_lambda_function" "sns_subscriber_lambda" {
  filename         = "sns_subscriber_lambda.zip"  # Path to your subscriber Lambda deployment package
  function_name    = "sns_subscriber_function"
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "index.handler"
  runtime          = "nodejs14.x"
  source_code_hash = filebase64sha256("sns_subscriber_lambda.zip")

  tags = {
    Name = "SnsSubscriberLambda"
  }
}

# Subscribe Lambda to SNS Topic
resource "aws_sns_topic_subscription" "lambda_subscription" {
  topic_arn = aws_sns_topic.upload_complete_topic.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sns_subscriber_lambda.arn
}

# Lambda Execution Role with SNS and S3 Permissions
resource "aws_iam_role" "lambda_exec_role" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action    = "sts:AssumeRole",
        Effect    = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Attach policies to allow Lambda to work with SNS and S3
resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "sns:Publish"
        ],
        Resource = [
          aws_s3_bucket.fariha_assign6_bucket.arn,
          "${aws_s3_bucket.fariha_assign6_bucket.arn}/*",
          aws_sns_topic.upload_complete_topic.arn
        ]
      }
    ]
  })
}


/***************************
 * PART 8: MONITORING & SECURITY 
 ***************************/
 
/***************************
 * 8.1: 
    - 
 ***************************/

/***************************
 * 8.2: 
    - 
 ***************************/

