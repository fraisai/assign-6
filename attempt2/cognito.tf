# Part 1: Cognito User Pool and App Client for JWT authentication
resource "aws_cognito_user_pool" "user_pool" {
  name = "example-user-pool"
}

resource "aws_cognito_user_pool_client" "user_pool_client" {
  user_pool_id               = aws_cognito_user_pool.user_pool.id
  name                       = "example-app-client"
  generate_secret            = false
  allowed_oauth_flows        = ["client_credentials"]
  allowed_oauth_scopes       = ["email", "openid", "aws.cognito.signin.user.admin"]
  allowed_oauth_flows_user_pool_client = true
}

