exports.handler = async (event) => {
    try {
        console.log("Received event:", JSON.stringify(event, null, 2));

        // Process each message
        for (const record of event.Records) {
            const snsMessage = record.Sns.Message;
            console.log("SNS Message:", snsMessage);

            // Add any additional processing logic here

            // Example: Parse the message if it's JSON
            const message = JSON.parse(snsMessage);
            console.log("Parsed Message:", message);
        }

        return {
            statusCode: 200,
            body: JSON.stringify({ message: 'Messages processed successfully.' }),
        };
    } catch (error) {
        console.error("Error processing message:", error);
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Failed to process messages.' }),
        };
    }
};
