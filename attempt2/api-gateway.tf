# Part 4: API Gateway with Lambda Integration and Cognito Authorization
resource "aws_api_gateway_rest_api" "rest_api" {
  name = "example-api"
}

resource "aws_api_gateway_resource" "api_resource" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  parent_id   = aws_api_gateway_rest_api.rest_api.root_resource_id
  path_part   = "api"
}

resource "aws_api_gateway_method" "post_method" {
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  resource_id   = aws_api_gateway_resource.api_resource.id
  http_method   = "POST"
  authorization = "COGNITO_USER_POOLS"
  authorizer_id = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  resource_id = aws_api_gateway_resource.api_resource.id
  http_method = aws_api_gateway_method.post_method.http_method
  integration_http_method = "POST"
  type        = "AWS_PROXY"
  uri         = aws_lambda_function.api_lambda.invoke_arn
}

# Cognito Authorizer for API Gateway
resource "aws_api_gateway_authorizer" "cognito_authorizer" {
  name          = "CognitoAuthorizer"
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  type          = "COGNITO_USER_POOLS"
  provider_arns = [aws_cognito_user_pool.user_pool.arn]
  identity_source = "method.request.header.Authorization"
}

# Deploy API Gateway
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on   = [aws_api_gateway_integration.lambda_integration]
  rest_api_id  = aws_api_gateway_rest_api.rest_api.id
  stage_name   = "prod"
}

