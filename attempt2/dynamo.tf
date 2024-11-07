# Part 3: DynamoDB Table for data storage
resource "aws_dynamodb_table" "api_table" {
  name         = "api-data-table"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

