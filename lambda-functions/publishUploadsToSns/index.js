const AWS = require('aws-sdk');

const s3 = new AWS.S3();
const sns = new AWS.SNS();
const snsTopicArn = 'arn:aws:sns:eu-north-1:866934333672:fariha-complete-topic'; // Replace with your SNS topic ARN

// Main Lambda handler
exports.handler = async (event) => {
    try {
        // Loop through each record in the event
        for (const record of event.Records) {
            const bucket = record.s3.bucket.name;
            const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));
            
            // Get the uploaded object from S3
            const params = {
                Bucket: bucket,
                Key: key,
            };

            const data = await s3.getObject(params).promise();
            const fileContent = data.Body.toString('utf-8'); // Convert buffer to string
            
            // Process the file content (you can modify this based on your processing logic)
            const message = `File uploaded: ${key}\nContent:\n${fileContent}`;
            
            // Publish to SNS
            const snsParams = {
                Message: message,
                TopicArn: snsTopicArn,
            };

            await sns.publish(snsParams).promise();
            console.log(`Message published to SNS: ${message}`);
        }

        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'File processed and message published to SNS.' }),
        };
    } catch (error) {
        console.error(`Error processing file: ${error.message}`);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Error processing file.' }),
        };
    }
};
