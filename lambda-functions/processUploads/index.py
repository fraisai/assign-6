import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
table_name = os.environ['DYNAMODB_TABLE']
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    # Get the bucket name and object key from the event
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    # Process the object (e.g., get metadata)
    metadata = {
        'file_id': key,  # You can change this based on your needs
        'bucket': bucket
    }
    
    # Store metadata in DynamoDB
    table.put_item(Item=metadata)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Metadata stored successfully!')
    }
