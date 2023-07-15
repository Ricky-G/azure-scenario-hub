# Azure Event Grid with Private Endpoints

This section of the repository demonstrates how to configure an Azure Event Grid within a Virtual Network (VNet) and expose it exclusively via a private endpoint. It showcases three different methods to push events from the Event Grid in a private mode, given that Event Grid cannot directly push to a private endpoint. 

The three methods are:

1. Push to a public endpoint HTTP trigger Logic App.
2. Push to a public endpoint Azure API Management (APIM) API.
3. Push to a Service Bus topic located in the same VNet.

All three routes will be locked down to exclusively accept traffic from the Event Grid and its managed identity.

Additionally, this section will provide the Infrastructure as Code (IaC) necessary to set up these configurations, a sample service to generate events to Event Grid, and another service to consume the events.

## Prerequisites

Ensure you have the following before beginning:

- An active Azure subscription.
- Azure CLI installed on your machine.
- Familiarity with Azure Event Grid, Logic Apps, APIM, Service Bus, and VNets.

## Setup

Detailed setup instructions for each component are available in their respective directories:

### Event Grid Setup

Refer to [this guide](./event-grid-setup.md) for setting up the Event Grid within a VNet.

### Private Endpoint Setup

Instructions for exposing the Event Grid through a private endpoint are available [here](./private-endpoint-setup.md).

### Logic App Setup

Refer to [this guide](./logic-app-setup.md) for creating a public endpoint HTTP trigger Logic App.

### APIM API Setup

Instructions for creating a public endpoint APIM API are available [here](./apim-api-setup.md).

### Service Bus Setup

Refer to [this guide](./service-bus-setup.md) for creating a Service Bus topic within the same VNet.

### Sample Event Generator Service

A guide for setting up the sample service to generate events to Event Grid is available [here](./event-generator-service-setup.md).

### Sample Event Consumer Service

Instructions for setting up the sample service to consume events from the Event Grid are available [here](./event-consumer-service-setup.md).

## Lockdown

Now that our architecture is set up, we will lock down the Logic App, the APIM API, and the Service Bus to only accept traffic from the Event Grid and its managed identity.

Refer to [this guide](./lockdown-setup.md) for detailed instructions on how to lock down these components.

## Conclusion

By following these instructions, you should now have an Azure Event Grid securely configured within a VNet, capable of pushing events through a private endpoint, and capable of securely communicating with a Logic App, an APIM API, and a Service Bus topic. Additionally, you have set up a sample service to generate and consume events from the Event Grid.

Feel free to explore, modify, and implement these scripts for your own projects. Please submit any issues or suggestions to the GitHub repository to continually improve this resource for everyone.

Enjoy building!
