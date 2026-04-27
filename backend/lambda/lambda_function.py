import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_TABLE', 'visitor-counter')
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    response = table.update_item(
        Key={'id': 'visitor-counter'},
        UpdateExpression="ADD #v :inc",
        ExpressionAttributeNames={'#v': 'views'},
        ExpressionAttributeValues={':inc': 1},
        ReturnValues="UPDATED_NEW"
    )

    count = int(response['Attributes']['views'])

    return {
        "statusCode": 200,
        "headers": {
            "Access-Control-Allow-Origin": "*"
        },
        "body": json.dumps({"count": count})
    }