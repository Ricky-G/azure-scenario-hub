# Load Testing Strategy for Azure Integration Services

## Overview
This document outlines a comprehensive load testing approach for the Azure Integration Services scenario, testing both HTTP endpoints and monitoring the complete message flow through Service Bus to measure EP1 App Service Plan performance.

## Testing Architecture

### Test Components
1. **HTTP Endpoint Load Testing** - Direct calls to audits-adaptor and history-adaptor
2. **End-to-End Flow Testing** - Measure complete message processing latency
3. **Scaling Performance Analysis** - Test at various instance counts
4. **Application Insights Monitoring** - Real-time metrics and failure analysis

### Test Tools
- **Primary**: Azure Load Testing with Locust scripts
- **Secondary**: Custom PowerShell scripts for quick tests
- **Monitoring**: Application Insights queries and dashboards

## Load Test Scenarios

### Scenario 1: HTTP Endpoint Performance
**Target**: Test direct HTTP response times for both adaptors
- Audits endpoint: `POST /api/audits`
- History endpoint: `POST /api/history`

### Scenario 2: End-to-End Message Flow
**Target**: Measure complete processing time from HTTP request to Service Bus message processing
- Track custom telemetry events to measure E2E latency
- Monitor Service Bus queue depths and processing rates

### Scenario 3: Mixed Workload
**Target**: Realistic load with both endpoints under concurrent stress
- 70% Audits traffic, 30% History traffic (adjust based on your expected ratio)
- Gradual ramp-up and sustained load periods

### Scenario 4: Stress Testing
**Target**: Find breaking points and observe auto-scaling behavior
- Progressive load increase until failure points
- Monitor EP1 plan scaling behavior

## Test Parameters

### Load Patterns
1. **Baseline** - 10 users, 60 seconds
2. **Normal Load** - 50 users, 5 minutes  
3. **Peak Load** - 100 users, 10 minutes
4. **Stress Test** - 200+ users, 15 minutes

### Test Data
- Varying payload sizes (1KB, 10KB, 50KB)
- Different message types and complexity
- Realistic business data patterns

### Success Criteria
- **Response Time**: < 500ms for 95% of requests
- **Error Rate**: < 1% failure rate
- **Throughput**: Target messages/second based on business requirements
- **E2E Latency**: < 2 seconds from HTTP request to Service Bus processing completion

## Implementation Options

### Option 1: Azure Load Testing (Recommended)
**Pros**:
- Integrated with Azure monitoring
- Scalable load generation
- Built-in reporting and analysis
- Integration with Application Insights
- CI/CD pipeline integration

**Cons**:
- Requires Azure Load Testing resource
- Additional cost for load testing service

### Option 2: Locust Scripts (Cost-effective)
**Pros**:
- Free and open source
- Highly customizable
- Can run from local machine or Azure VM
- Python-based, easy to modify

**Cons**:
- Manual setup and monitoring
- Limited built-in Azure integration
- Requires separate monitoring setup

### Option 3: Custom PowerShell Scripts (Quick & Simple)
**Pros**:
- Immediate implementation
- Full control over test logic
- Easy to modify and iterate
- Good for initial testing

**Cons**:
- Limited load generation capability
- Basic reporting
- Manual result analysis

## Recommended Implementation Plan

### Phase 1: Quick Validation (PowerShell)
Create simple PowerShell scripts for immediate testing and validation.

### Phase 2: Comprehensive Testing (Azure Load Testing + Locust)
Implement full Azure Load Testing with custom Locust scripts for thorough performance analysis.

### Phase 3: Continuous Testing (CI/CD Integration)
Integrate load tests into deployment pipelines for ongoing performance validation.

## Monitoring and Analysis

### Key Metrics to Track
1. **Function App Metrics**:
   - Execution count and duration
   - Memory and CPU usage
   - Cold start frequency and duration
   - Instance count scaling behavior

2. **Service Bus Metrics**:
   - Message throughput and latency
   - Queue depth and processing rate
   - Dead letter queue activity

3. **Application Insights**:
   - Custom telemetry events for E2E tracking
   - Exception rates and types
   - Dependency call performance

4. **Infrastructure Metrics**:
   - EP1 plan scaling behavior
   - Network performance through private endpoints
   - Resource utilization patterns

### Analysis Approach
- Compare performance across different load levels
- Identify bottlenecks and scaling limits
- Correlate infrastructure scaling with performance metrics
- Generate actionable recommendations for optimization

## Cost Optimization
- Use Azure Load Testing for comprehensive tests (pay per use)
- Use Locust scripts for development and quick iterations (free)
- Schedule intensive tests during off-peak hours
- Clean up test resources immediately after completion
