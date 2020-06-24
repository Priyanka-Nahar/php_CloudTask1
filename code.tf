provider "aws" {
  profile = "priyanka"
  region  = "ap-south-1"
}

// Creating the EC2 key

variable "keyname" {
default = "key"
}



// Creating EC2 key

resource "tls_private_key" "keypair" {
 algorithm = "RSA"
}
resource "aws_key_pair" "keypair" {
  key_name   = "key"
  public_key = tls_private_key.keypair.public_key_openssh
}


//ec2 instance
resource "aws_instance" "server" {
  ami                = "ami-0447a12f28fddb066"
  instance_type      = "t2.micro"
  security_groups    = ["SG"]
  key_name           =  aws_key_pair.keypair.key_name

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.keypair.private_key_pem
    host        = aws_instance.server.public_ip
           }

 provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"
    ]
     }
 tags  = {
   Name = "server"
            }
}

//volume ebs

resource "aws_ebs_volume" "instance_volume" {
 availability_zone = aws_instance.server.availability_zone
 size = 1
 tags = {
        Name = "instance_volume"
 }
}

resource "aws_volume_attachment" "attach_volume" {
 depends_on = [
       aws_instance.server
      ]
  device_name = "/dev/sde"
  volume_id = aws_ebs_volume.instance_volume.id
  instance_id = aws_instance.server.id
  force_detach =true
 }

resource"null_resource" "for" {
 depends_on = [
        aws_ebs_volume.instance_volume
    ]
  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.keypair.private_key_pem
    host        = aws_instance.server.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4   /dev/xvdf",
      "sudo mount /dev/xvdf  /var/www/html",
      "sudo rm -rf  /var/www/html/*",
      "sudo git clone https://github.com/Priyanka-Nahar/php_CloudTask1.git    /var/www/html/"
]
    }
}

resource "null_resource" "nullremoteaccess" {
  depends_on=[
          null_resource.for
          ]
   }

//Creating AWS Security Group:
resource "aws_security_group" "allow_traffic" {
 name        = "SG"
 description = "Allow inbound traffic"
 ingress {
   description = "TCP"
   from_port   = 80
   to_port     = 80
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
    }
 ingress {
   description = "SSH"
   from_port   = 22
   to_port     = 22
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
     }
 ingress {
   description = "HTTPS"
   from_port   = 443
   to_port     = 443
   protocol    = "tcp"
   cidr_blocks = ["0.0.0.0/0"]
     }
 egress {
   from_port   = 0
   to_port     = 0
   protocol    = "-1"
   cidr_blocks = ["0.0.0.0/0"]
    }
 tags = {
    Name = "allow_traffic"
}
}


//S3 bucket creation

resource "aws_s3_bucket" "sbucket" {
  bucket = "svolume"
  acl    = "public-read"
  region = "ap-south-1"
  tags = {
    Name = "s3volume"
  }
}

resource "null_resource" "download" {
  provisioner "local-exec" {
    command = "git clone https://github.com/Priyanka-Nahar/php_CloudTask1.git task"
 }
}

resource "aws_s3_bucket_object" "upload" {
 depends_on = [
    aws_s3_bucket.sbucket, null_resource.download
  ]
    bucket  = aws_s3_bucket.sbucket.bucket
    key     = "image"
    source  = "task/terraform-x-aws.png"
    acl     = "public-read"
}


resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "sbucket.s3.amazonaws.com"
    origin_id   = "s3-sbucket"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Some comment"
 
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-sbucket"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Cache behavior with precedence 0
  ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "s3-sbucket"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }


  tags = {
    Environment = "production"
  }
  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["US", "CA", "GB", "DE"]
    }
  }


  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource  "null_resource"  "resource"{
depends_on=[
            null_resource.nullremoteaccess,
            aws_cloudfront_distribution.s3_distribution

     ]

provisioner "local-exec" {
    command = "start chrome ${aws_instance.server.public_ip}"
  }
}