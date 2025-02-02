terraform {
  backend "s3" {
    bucket = "bucketbackend123"  # Your S3 bucket name
    key    = "backend"  # Path within the bucket to store the state file
    region = "us-east-2"  # The AWS region where your S3 bucket is located
    encrypt = true  # Enable encryption for the state file
    #dynamodb_table = "terraform-state-lock"  # DynamoDB table for state locking (optional)
  }
}