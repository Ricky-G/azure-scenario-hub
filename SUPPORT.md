# Support

Welcome to Azure Scenario Hub! We're here to help you successfully deploy and use the Azure architecture scenarios in this repository.

## 🆘 Getting Help

### 📋 Before You Ask

1. **Check the Documentation**: Review the scenario-specific README files
2. **Search Existing Issues**: Look through [existing issues](../../issues) for similar problems
3. **Review Prerequisites**: Ensure you meet all the requirements listed in each scenario
4. **Check Azure Status**: Verify [Azure Service Health](https://status.azure.com/) for any ongoing issues

### 🐛 Reporting Issues

For bugs, problems, or unexpected behavior:

1. **Create a GitHub Issue**: Use our [issue templates](../../issues/new/choose)
2. **Provide Details**: Include the information requested in the template
3. **Be Specific**: Describe what you expected vs. what actually happened

### 💡 Feature Requests

Have an idea for a new scenario or enhancement?

1. **Check Existing Requests**: Review [existing feature requests](../../issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement)
2. **Create a Feature Request**: Use the feature request template
3. **Explain the Use Case**: Help us understand why this would be valuable

### 🤔 Questions and Discussions

For general questions, best practices, or discussions:

1. **GitHub Discussions**: Use [Discussions](../../discussions) for community Q&A
2. **Scenario-Specific Questions**: Comment on the relevant scenario's documentation

## 📞 Support Channels

| Type | Channel | Response Time |
|------|---------|---------------|
| 🐛 Bugs | [GitHub Issues](../../issues) | 1-3 business days |
| 💡 Features | [GitHub Issues](../../issues) | 1 week |
| ❓ Questions | [GitHub Discussions](../../discussions) | Best effort |
| 🔒 Security | See [SECURITY.md](SECURITY.md) | 48 hours |

## 📋 When Creating Issues

Please include:

### For Bug Reports
- **Scenario Name**: Which scenario you're working with
- **Azure Region**: Where you're deploying
- **Error Messages**: Complete error text and stack traces
- **Steps to Reproduce**: Detailed steps that led to the issue
- **Environment**: OS, Azure CLI version, Bicep version
- **Expected Behavior**: What should have happened
- **Actual Behavior**: What actually happened

### For Feature Requests
- **Scenario Type**: What kind of Azure architecture
- **Use Case**: Why this scenario would be useful
- **Acceptance Criteria**: What would make this complete
- **Priority**: How important this is to you

## 🔧 Self-Help Resources

### Documentation
- [Azure Documentation](https://learn.microsoft.com/azure/)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
- [Azure CLI Reference](https://learn.microsoft.com/cli/azure/)

### Common Issues and Solutions

#### Deployment Failures
1. **Check Permissions**: Ensure you have Contributor access to the subscription/resource group
2. **Verify Quotas**: Check if you've hit any Azure resource quotas
3. **Review Names**: Ensure resource names are unique and follow Azure naming conventions
4. **Check Regions**: Verify the Azure region supports all required services

#### Authentication Issues
1. **Azure CLI Login**: Run `az login` and verify you're in the correct subscription
2. **Permissions**: Ensure your account has the necessary RBAC permissions
3. **Service Principal**: If using service principals, verify credentials are correct

#### Resource Conflicts
1. **Unique Names**: Many Azure resources require globally unique names
2. **Existing Resources**: Check if resources already exist in your subscription
3. **Cleanup**: Remove any partially deployed resources before retrying

## 🎯 Best Practices for Getting Help

1. **Be Patient**: Our maintainers are volunteers with day jobs
2. **Be Respectful**: Follow our [Code of Conduct](CODE_OF_CONDUCT.md)
3. **Be Detailed**: More information helps us help you faster
4. **Follow Up**: Update your issues with additional information or resolution
5. **Help Others**: Share your knowledge by answering questions from other users

## 🌟 Community Guidelines

- **Be Kind**: Treat everyone with respect and kindness
- **Be Constructive**: Provide helpful feedback and suggestions
- **Be Patient**: Remember that everyone is learning
- **Share Knowledge**: Help others who might have similar questions
- **Follow Guidelines**: Adhere to our community standards

## 📚 Learning Resources

### Azure Fundamentals
- [Microsoft Learn - Azure Fundamentals](https://learn.microsoft.com/training/paths/azure-fundamentals/)
- [Azure Architecture Center](https://learn.microsoft.com/azure/architecture/)

### Infrastructure as Code
- [Bicep Learning Path](https://learn.microsoft.com/training/paths/bicep-deploy/)
- [ARM Template Best Practices](https://learn.microsoft.com/azure/azure-resource-manager/templates/best-practices)

### DevOps and Automation
- [Azure DevOps](https://learn.microsoft.com/azure/devops/)
- [GitHub Actions for Azure](https://learn.microsoft.com/azure/developer/github/github-actions)

## 🤝 Contributing Back

Found a solution to a common problem? Consider:

1. **Update Documentation**: Submit a PR to improve existing docs
2. **Share Solutions**: Add your solution to discussions
3. **Create Scenarios**: Contribute new scenarios that others might need
4. **Review PRs**: Help review and test contributions from others

---

**Remember**: This is a community-driven project. Your contributions, feedback, and participation make it better for everyone! 🚀
