# Logic Apps End To End Monitoring


![Logic Apps End To End Monitoring](logic-apps-end-to-end-monitoring-scenario.drawio.svg)

## Prerequisites

Ensure you have the following before beginning:

- An active Azure subscription.
- Azure CLI installed on your machine.
- Familiarity with Logic Apps.

## Getting Started

1. Clone this repository to your local machine.

``
az deployment sub create `
    --name logicapps-end-to-end-monitoring-deployment `
    --location eastus `
    --template-file main.bicep `
    --parameters location='eastus' `
                 resourceGroupName='rg-integration-test' `
                 storageAccountForLogicAppsName='integrationtststract23' `
                 logAnalyticsWorkspaceName='IntegrationTestLogAnalyticsWorkspace' `
                 logicAppFileShareName='logicappsfileshare' `
                 appServicePlanName='integrationappserviceplan1'

```

## TODO
The Terraform code for this repository is still a work in progress.

## Contributing

This repository is open to contributions. Feel free to submit a pull request or open an issue if you find any bugs or have any suggestions.

## License

This repository is licensed under the MIT License. See the LICENSE file for more information.