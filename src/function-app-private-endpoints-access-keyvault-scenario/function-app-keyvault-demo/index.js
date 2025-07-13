const { DefaultAzureCredential } = require('@azure/identity');
const { SecretClient } = require('@azure/keyvault-secrets');

/**
 * Simple demo function that retrieves a secret from Key Vault using Managed Identity
 * and private endpoint connectivity. This demonstrates secure access to Key Vault
 * without exposing credentials or using public internet routes.
 */
module.exports = async function (context, req) {
    context.log(`HTTP function processed request for url "${req.url}"`);

    try {
        // Get Key Vault URL from environment variables (set in Bicep template)
        const keyVaultUrl = process.env.KEY_VAULT_URL;
        if (!keyVaultUrl) {
            context.res = {
                status: 500,
                body: JSON.stringify({
                    error: 'KEY_VAULT_URL environment variable not found',
                    message: 'Ensure the Function App is properly configured with Key Vault URL',
                    availableEnvVars: Object.keys(process.env).filter(key => key.includes('KEY') || key.includes('VAULT') || key.includes('AZURE'))
                })
            };
            return;
        }

        context.log(`Connecting to Key Vault: ${keyVaultUrl}`);

        // Use DefaultAzureCredential with User Assigned Managed Identity
        // The AZURE_CLIENT_ID environment variable is automatically used
        const credential = new DefaultAzureCredential();
        
        // Create Key Vault client - this will use the private endpoint
        const secretClient = new SecretClient(keyVaultUrl, credential);

        // Retrieve the demo secret (created in Bicep template)
        const secretName = 'demo-secret';
        context.log(`Retrieving secret: ${secretName}`);
        
        const secret = await secretClient.getSecret(secretName);
        
        if (!secret.value) {
            context.res = {
                status: 404,
                body: JSON.stringify({
                    error: 'Secret not found or empty',
                    secretName: secretName
                })
            };
            return;
        }

        // Success! Return the secret metadata (not the actual value for security)
        context.res = {
            status: 200,
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                message: 'Successfully retrieved secret from Key Vault via private endpoint!',
                secretName: secretName,
                keyVaultUrl: keyVaultUrl,
                secretMetadata: {
                    id: secret.properties.id,
                    enabled: secret.properties.enabled,
                    createdOn: secret.properties.createdOn,
                    updatedOn: secret.properties.updatedOn
                },
                // For demo purposes, show first/last chars of secret
                secretPreview: secret.value ? `${secret.value.substring(0, 3)}...${secret.value.substring(secret.value.length - 3)}` : 'empty',
                privateEndpointAccess: true,
                managedIdentityUsed: true,
                timestamp: new Date().toISOString()
            })
        };

    } catch (error) {
        context.log.error('Error retrieving secret from Key Vault:', error);
        
        // Provide detailed error information for troubleshooting
        context.res = {
            status: 500,
            body: JSON.stringify({
                error: 'Failed to retrieve secret from Key Vault',
                message: error.message,
                errorCode: error.code,
                keyVaultUrl: process.env.KEY_VAULT_URL,
                managedIdentityClientId: process.env.AZURE_CLIENT_ID,
                troubleshooting: {
                    checkManagedIdentity: 'Verify the Function App has a User Assigned Managed Identity',
                    checkKeyVaultAccess: 'Verify the Managed Identity has Key Vault Secrets User role',
                    checkPrivateEndpoint: 'Verify the private endpoint is properly configured',
                    checkNetworking: 'Verify VNet integration is working correctly'
                },
                timestamp: new Date().toISOString()
            })
        };
    }
};
