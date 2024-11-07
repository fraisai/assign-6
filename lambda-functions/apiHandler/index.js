const AWS = require('aws-sdk');
const dynamoDB = new AWS.DynamoDB.DocumentClient();
const tableName = 'YourDynamoDBTableName'; // Replace with your DynamoDB table name

// Function to validate user data
const validateUserData = (userData) => {
    const requiredFields = ['username', 'email', 'age'];

    for (const field of requiredFields) {
        if (!(field in userData)) {
            return { isValid: false, message: `Missing required field: ${field}` };
        }
    }

    if (typeof userData.age !== 'number' || userData.age < 0) {
        return { isValid: false, message: 'Age must be a non-negative integer.' };
    }

    // Add more validation rules as needed

    return { isValid: true, message: '' };
};

// Function to process user data
const processUserData = (userData) => {
    // Example processing: convert email to lowercase
    userData.email = userData.email.toLowerCase();
    return userData;
};

// Function to store user data in DynamoDB
const storeUserData = async (userData) => {
    const params = {
        TableName: tableName,
        Item: userData,
    };

    try {
        await dynamoDB.put(params).promise();
        return { success: true };
    } catch (error) {
        return { success: false, error: error.message };
    }
};

// Main Lambda handler
exports.handler = async (event) => {
    // Parse the incoming event
    const userData = JSON.parse(event.body);

    // Validate user data
    const validation = validateUserData(userData);
    if (!validation.isValid) {
        return {
            statusCode: 400,
            body: JSON.stringify({ error: validation.message }),
        };
    }

    // Process user data
    const processedData = processUserData(userData);

    // Store user data in DynamoDB
    const storeResult = await storeUserData(processedData);
    if (!storeResult.success) {
        return {
            statusCode: 500,
            body: JSON.stringify({ error: 'Failed to store data in DynamoDB', details: storeResult.error }),
        };
    }

    return {
        statusCode: 200,
        body: JSON.stringify({ message: 'User data stored successfully', data: processedData }),
    };
};
