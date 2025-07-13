"""
Azure Integration Services Load Test - Locust Script

This script tests the Azure Function Apps HTTP endpoints and measures
end-to-end message processing performance through Service Bus.

Usage:
  locust -f locustfile.py --host=https://your-function-app-url.azurewebsites.net

Environment Variables Required:
  - AUDITS_FUNCTION_URL: URL for audits-adaptor function
  - HISTORY_FUNCTION_URL: URL for history-adaptor function
  - APPINSIGHTS_CONNECTION_STRING: Application Insights connection string (optional, for custom telemetry)
"""

import os
import time
import json
import uuid
from datetime import datetime, timezone
from locust import HttpUser, task, between, events
from locust.runners import MasterRunner
import requests

class IntegrationServicesUser(HttpUser):
    wait_time = between(1, 3)  # Wait 1-3 seconds between requests
    
    def on_start(self):
        """Initialize test data and endpoints"""
        self.audits_url = os.getenv('AUDITS_FUNCTION_URL', 'http://localhost:7071')
        self.history_url = os.getenv('HISTORY_FUNCTION_URL', 'http://localhost:7072')
        
        # Remove '/api/audits' or '/api/history' from URLs if present
        self.audits_base = self.audits_url.rstrip('/api/audits').rstrip('/')
        self.history_base = self.history_url.rstrip('/api/history').rstrip('/')
        
        self.user_id = str(uuid.uuid4())
        self.session_id = str(uuid.uuid4())
        
        print(f"Starting load test for user {self.user_id}")
        print(f"Audits base URL: {self.audits_base}")
        print(f"History base URL: {self.history_base}")

    @task(7)  # 70% of traffic goes to audits
    def test_audits_endpoint(self):
        """Test the audits-adaptor HTTP endpoint"""
        payload = self.generate_audit_payload()
        
        start_time = time.time()
        
        with self.client.post(
            f"{self.audits_base}/api/audits",
            json=payload,
            headers={"Content-Type": "application/json"},
            catch_response=True,
            name="POST /api/audits"
        ) as response:
            end_time = time.time()
            
            if response.status_code == 200:
                # Track successful request
                self.track_custom_metric("audit_request_success", end_time - start_time, payload.get('auditId'))
            else:
                response.failure(f"Got status code {response.status_code}")
                self.track_custom_metric("audit_request_failure", end_time - start_time, payload.get('auditId'))

    @task(3)  # 30% of traffic goes to history
    def test_history_endpoint(self):
        """Test the history-adaptor HTTP endpoint"""
        payload = self.generate_history_payload()
        
        start_time = time.time()
        
        with self.client.post(
            f"{self.history_base}/api/history",
            json=payload,
            headers={"Content-Type": "application/json"},
            catch_response=True,
            name="POST /api/history"
        ) as response:
            end_time = time.time()
            
            if response.status_code == 200:
                # Track successful request
                self.track_custom_metric("history_request_success", end_time - start_time, payload.get('historyId'))
            else:
                response.failure(f"Got status code {response.status_code}")
                self.track_custom_metric("history_request_failure", end_time - start_time, payload.get('historyId'))

    @task(1)  # Occasional health checks
    def test_health_endpoints(self):
        """Test health endpoints for monitoring"""
        # Test audits health
        with self.client.get(
            f"{self.audits_base}/api/health",
            catch_response=True,
            name="GET /api/health (audits)"
        ) as response:
            if response.status_code != 200:
                response.failure(f"Audits health check failed: {response.status_code}")
        
        # Test history health  
        with self.client.get(
            f"{self.history_base}/api/health",
            catch_response=True,
            name="GET /api/health (history)"
        ) as response:
            if response.status_code != 200:
                response.failure(f"History health check failed: {response.status_code}")

    def generate_audit_payload(self):
        """Generate realistic audit request payload"""
        return {
            "auditId": str(uuid.uuid4()),
            "userId": self.user_id,
            "sessionId": self.session_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "action": "user_action",
            "resource": "test_resource",
            "details": {
                "operation": "load_test",
                "metadata": {
                    "source": "locust_load_test",
                    "test_run": int(time.time()),
                    "user_agent": "Locust Load Test"
                }
            },
            "severity": "Info",
            "correlationId": str(uuid.uuid4())
        }

    def generate_history_payload(self):
        """Generate realistic history request payload"""
        return {
            "historyId": str(uuid.uuid4()),
            "userId": self.user_id,
            "sessionId": self.session_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "eventType": "data_change",
            "entityId": str(uuid.uuid4()),
            "entityType": "test_entity",
            "changes": [
                {
                    "field": "status",
                    "oldValue": "pending",
                    "newValue": "processed",
                    "changeType": "update"
                },
                {
                    "field": "lastModified",
                    "oldValue": None,
                    "newValue": datetime.now(timezone.utc).isoformat(),
                    "changeType": "create"
                }
            ],
            "metadata": {
                "source": "locust_load_test",
                "test_run": int(time.time()),
                "operation": "load_test_data_change"
            },
            "correlationId": str(uuid.uuid4())
        }

    def track_custom_metric(self, metric_name, duration, correlation_id):
        """Track custom metrics for analysis"""
        # This could be extended to send custom telemetry to Application Insights
        # For now, just log to locust's built-in stats
        events.request.fire(
            request_type="CUSTOM",
            name=metric_name,
            response_time=duration * 1000,  # Convert to milliseconds
            response_length=0,
            exception=None,
            context={"correlation_id": correlation_id}
        )

# Event handlers for custom reporting
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print("Starting Azure Integration Services Load Test")
    print(f"Target URLs:")
    print(f"  Audits: {os.getenv('AUDITS_FUNCTION_URL', 'Not Set')}")
    print(f"  History: {os.getenv('HISTORY_FUNCTION_URL', 'Not Set')}")

@events.test_stop.add_listener  
def on_test_stop(environment, **kwargs):
    print("Load test completed!")
    print("Check Application Insights for detailed telemetry and end-to-end metrics")

# Custom user class for stress testing
class StressTestUser(IntegrationServicesUser):
    """Stress test user with higher frequency and larger payloads"""
    wait_time = between(0.1, 0.5)  # Much faster requests
    
    def generate_audit_payload(self):
        """Generate larger payload for stress testing"""
        base_payload = super().generate_audit_payload()
        # Add larger data to stress test
        base_payload["details"]["large_data"] = "x" * 10000  # 10KB of data
        return base_payload
    
    def generate_history_payload(self):
        """Generate larger payload for stress testing"""
        base_payload = super().generate_history_payload()
        # Add more changes for larger payload
        for i in range(50):  # Add 50 changes
            base_payload["changes"].append({
                "field": f"test_field_{i}",
                "oldValue": f"old_value_{i}",
                "newValue": f"new_value_{i}",
                "changeType": "update"
            })
        return base_payload
