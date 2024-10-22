
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

    lifecycle { # lifecycle block = use to avoid unwanted scaling of your ASG
        create_before_destroy = true
            # Why use lifecyle block?
                # bc you cannot modify a launch configuration, so any changes to the definition force Terraform to create a new resource. create_before_destroy argument in the lifecycle block instructs Terraform to create the new version before destroying the original to avoid any service interruptions
                # use Terraform lifecycle arguments to avoid drift or accidental changes - since ASGs are dynamic and Terraform does not manage the underlying instances directly because every scaling action would introduce state drift. 
    }
}

# ASG configuration
resource "aws_autoscaling_group" "fariha_assign6_asg" {
  min_size             = 2
  max_size             = 3
  desired_capacity     = 2
  
  launch_template { # Launch Template
    id      = aws_launch_template.fariha_assign6_lt.id
    version = "$Latest"
  }

  vpc_zone_identifier  = aws_subnet.fariha_subnet_public
    # the subnets where the ASGs will launch new instances

  health_check_type    = "ELB"

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



/***************************
 * 1.3: MULTI-TIER APPLICATION DEPLOYMENT
    - Set up one tier for web servers and use a placement group for web tier instances for enhanced network performance. 
    - Set up another tier for the database layer
 ***************************/

/***************************
 * 1.4: AUTO HEALING
    - Configure EC2 Auto Recovery to automatically replace unhealthy instances using a health check based on EC2 status checks and ELB health checks. 
 ***************************/




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
 * 3.1: EBS & DATA REPLICATION
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


/***************************
 * 3.2.2: S3 VERSIONING & ENCRYPTION
    - Enable versioning for bucket to preserve data integrity
    - Enforce SSE-S3 or SSE-KMS encryption for all objects stored in the bucket
 ***************************/


/***************************
 * 3.3: REPLICATION & STATIC WEBSITE HOSTING
    - CRR: Set up cross-region replication for S3 buckets across 2 different regions to ensure disaster recovery
    - STATIC WEBSITE HOSTING: Host a static version of your application's frontend on S3 
 ***************************/


/***************************
 * PART 4: GLOBAL CONTENT DELIVERY with CLOUDFRONT
 ***************************/


/***************************
 * 4.1: CLOUDFRONT DISTRIBUTION SETUP
    - Create a CloudFront Distribution with your S3 bucket from Part 3 as the origin 
    - Set up custom cache invalidation to automatically clear cached objects during deployments
    - Implement geo-restrictions to control access based on user location
 ***************************/



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

/***************************
 * 7.2: 
    - 
 ***************************/


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

