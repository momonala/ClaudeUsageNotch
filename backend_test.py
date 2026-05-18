#!/usr/bin/env python3
"""
Backend API tests for Notchy Limit
Tests all endpoints against the public URL
"""
import requests
import sys
import time
from datetime import datetime

class NotchyLimitAPITester:
    def __init__(self, base_url="https://ai-limits-2.preview.emergentagent.com"):
        self.base_url = base_url
        self.api_url = f"{base_url}/api"
        self.tests_run = 0
        self.tests_passed = 0
        self.test_results = []

    def log(self, message, level="INFO"):
        """Log test messages"""
        timestamp = datetime.now().strftime("%H:%M:%S")
        print(f"[{timestamp}] {level}: {message}")

    def run_test(self, name, method, endpoint, expected_status, data=None, check_fn=None):
        """Run a single API test"""
        url = f"{self.api_url}{endpoint}"
        self.tests_run += 1
        self.log(f"Testing {name}...")
        
        try:
            if method == 'GET':
                response = requests.get(url, timeout=10)
            elif method == 'POST':
                response = requests.post(url, json=data, timeout=10)
            else:
                raise ValueError(f"Unsupported method: {method}")

            success = response.status_code == expected_status
            
            if success and check_fn:
                try:
                    response_data = response.json()
                    check_result = check_fn(response_data)
                    if not check_result:
                        success = False
                        self.log(f"❌ {name} - Response validation failed", "ERROR")
                        self.test_results.append({"name": name, "passed": False, "reason": "Response validation failed"})
                    else:
                        self.tests_passed += 1
                        self.log(f"✅ {name} - Passed (Status: {response.status_code})", "SUCCESS")
                        self.test_results.append({"name": name, "passed": True})
                except Exception as e:
                    success = False
                    self.log(f"❌ {name} - Validation error: {str(e)}", "ERROR")
                    self.test_results.append({"name": name, "passed": False, "reason": str(e)})
            elif success:
                self.tests_passed += 1
                self.log(f"✅ {name} - Passed (Status: {response.status_code})", "SUCCESS")
                self.test_results.append({"name": name, "passed": True})
            else:
                self.log(f"❌ {name} - Expected {expected_status}, got {response.status_code}", "ERROR")
                self.log(f"   Response: {response.text[:200]}", "DEBUG")
                self.test_results.append({"name": name, "passed": False, "reason": f"Expected {expected_status}, got {response.status_code}"})

            return success, response.json() if response.headers.get('content-type', '').startswith('application/json') else response

        except Exception as e:
            self.log(f"❌ {name} - Error: {str(e)}", "ERROR")
            self.test_results.append({"name": name, "passed": False, "reason": str(e)})
            return False, {}

    def test_health(self):
        """Test GET /api/health"""
        def check(data):
            return (
                data.get("ok") is True and
                data.get("service") == "notchy-limit-api" and
                "time" in data
            )
        return self.run_test(
            "Health Check",
            "GET",
            "/health",
            200,
            check_fn=check
        )

    def test_stats(self):
        """Test GET /api/stats"""
        def check(data):
            required_keys = ["downloads", "waitlist_count", "providers", "repo_url", "releases_url"]
            return all(key in data for key in required_keys)
        
        success, response = self.run_test(
            "Get Stats",
            "GET",
            "/stats",
            200,
            check_fn=check
        )
        return success, response if success else {}

    def test_waitlist_valid(self):
        """Test POST /api/waitlist with valid email"""
        test_email = f"test_{int(time.time())}@example.com"
        
        def check(data):
            return (
                data.get("ok") is True and
                "deduped" in data and
                "waitlist_count" in data and
                data.get("waitlist_count") >= 1
            )
        
        success, response = self.run_test(
            "Waitlist - Valid Email (First Time)",
            "POST",
            "/waitlist",
            200,
            data={"email": test_email, "provider": "gemini"},
            check_fn=check
        )
        
        if success and response.get("deduped") is False:
            self.log(f"   First submission successful, deduped={response.get('deduped')}", "DEBUG")
        
        return success, test_email

    def test_waitlist_duplicate(self, email):
        """Test POST /api/waitlist with duplicate email"""
        def check(data):
            return (
                data.get("ok") is True and
                data.get("deduped") is True
            )
        
        return self.run_test(
            "Waitlist - Duplicate Email",
            "POST",
            "/waitlist",
            200,
            data={"email": email, "provider": "gemini"},
            check_fn=check
        )

    def test_waitlist_invalid(self):
        """Test POST /api/waitlist with invalid email"""
        return self.run_test(
            "Waitlist - Invalid Email",
            "POST",
            "/waitlist",
            422,
            data={"email": "not-an-email", "provider": "gemini"}
        )

    def test_download_source(self):
        """Test GET /api/download/source"""
        url = f"{self.api_url}/download/source"
        self.tests_run += 1
        self.log("Testing Download Source ZIP...")
        
        try:
            response = requests.get(url, timeout=15, stream=True)
            
            if response.status_code != 200:
                self.log(f"❌ Download Source - Expected 200, got {response.status_code}", "ERROR")
                self.test_results.append({"name": "Download Source", "passed": False, "reason": f"Status {response.status_code}"})
                return False
            
            # Check Content-Type
            content_type = response.headers.get('Content-Type', '')
            if 'application/zip' not in content_type:
                self.log(f"❌ Download Source - Wrong Content-Type: {content_type}", "ERROR")
                self.test_results.append({"name": "Download Source", "passed": False, "reason": f"Wrong Content-Type: {content_type}"})
                return False
            
            # Check Content-Disposition
            content_disp = response.headers.get('Content-Disposition', '')
            if 'notchy-limit-source.zip' not in content_disp:
                self.log(f"❌ Download Source - Wrong Content-Disposition: {content_disp}", "ERROR")
                self.test_results.append({"name": "Download Source", "passed": False, "reason": f"Wrong Content-Disposition"})
                return False
            
            # Check body size (should be > 10KB)
            content_length = int(response.headers.get('Content-Length', 0))
            if content_length < 10240:
                self.log(f"❌ Download Source - File too small: {content_length} bytes", "ERROR")
                self.test_results.append({"name": "Download Source", "passed": False, "reason": f"File too small: {content_length} bytes"})
                return False
            
            self.tests_passed += 1
            self.log(f"✅ Download Source - Passed (Size: {content_length} bytes)", "SUCCESS")
            self.test_results.append({"name": "Download Source", "passed": True})
            return True
            
        except Exception as e:
            self.log(f"❌ Download Source - Error: {str(e)}", "ERROR")
            self.test_results.append({"name": "Download Source", "passed": False, "reason": str(e)})
            return False

    def test_download_dmg(self):
        """Test GET /api/download/dmg"""
        url = f"{self.api_url}/download/dmg"
        self.tests_run += 1
        self.log("Testing Download DMG Redirect...")
        
        try:
            response = requests.get(url, timeout=10, allow_redirects=False)
            
            if response.status_code != 302:
                self.log(f"❌ Download DMG - Expected 302, got {response.status_code}", "ERROR")
                self.test_results.append({"name": "Download DMG", "passed": False, "reason": f"Status {response.status_code}"})
                return False
            
            location = response.headers.get('Location', '')
            if 'github.com' not in location.lower() or 'releases' not in location.lower():
                self.log(f"❌ Download DMG - Invalid redirect: {location}", "ERROR")
                self.test_results.append({"name": "Download DMG", "passed": False, "reason": f"Invalid redirect"})
                return False
            
            self.tests_passed += 1
            self.log(f"✅ Download DMG - Passed (Redirects to: {location})", "SUCCESS")
            self.test_results.append({"name": "Download DMG", "passed": True})
            return True
            
        except Exception as e:
            self.log(f"❌ Download DMG - Error: {str(e)}", "ERROR")
            self.test_results.append({"name": "Download DMG", "passed": False, "reason": str(e)})
            return False

    def test_repo(self):
        """Test GET /api/repo"""
        def check(data):
            return "repo_url" in data and "releases_url" in data
        
        return self.run_test(
            "Get Repo Info",
            "GET",
            "/repo",
            200,
            check_fn=check
        )

    def test_feedback(self):
        """Test POST /api/feedback"""
        def check(data):
            return data.get("ok") is True
        
        return self.run_test(
            "Submit Feedback",
            "POST",
            "/feedback",
            200,
            data={"name": "Test User", "email": "test@example.com", "message": "This is a test feedback message."},
            check_fn=check
        )

    def test_stats_increment(self, initial_downloads):
        """Verify downloads counter incremented"""
        success, response = self.test_stats()
        if success:
            new_downloads = response.get("downloads", 0)
            if new_downloads > initial_downloads:
                self.log(f"✅ Downloads counter incremented: {initial_downloads} → {new_downloads}", "SUCCESS")
                return True
            else:
                self.log(f"⚠️  Downloads counter did not increment: {initial_downloads} → {new_downloads}", "WARNING")
                return False
        return False

    def run_all_tests(self):
        """Run all backend tests"""
        self.log("=" * 60)
        self.log("Starting Notchy Limit Backend API Tests")
        self.log(f"Base URL: {self.base_url}")
        self.log("=" * 60)
        
        # Test 1: Health check
        self.test_health()
        
        # Test 2: Get initial stats
        success, initial_stats = self.test_stats()
        initial_downloads = initial_stats.get("downloads", 0) if success else 0
        
        # Test 3-5: Waitlist tests
        success, test_email = self.test_waitlist_valid()
        if success:
            self.test_waitlist_duplicate(test_email)
        self.test_waitlist_invalid()
        
        # Test 6: Download source
        self.test_download_source()
        
        # Test 7: Download DMG
        self.test_download_dmg()
        
        # Test 8: Repo info
        self.test_repo()
        
        # Test 9: Feedback
        self.test_feedback()
        
        # Test 10: Verify stats increment
        time.sleep(1)  # Brief delay to ensure counter update
        self.test_stats_increment(initial_downloads)
        
        # Print summary
        self.log("=" * 60)
        self.log(f"Tests completed: {self.tests_passed}/{self.tests_run} passed")
        self.log("=" * 60)
        
        # Print failed tests
        failed_tests = [t for t in self.test_results if not t["passed"]]
        if failed_tests:
            self.log("Failed tests:", "ERROR")
            for test in failed_tests:
                self.log(f"  - {test['name']}: {test.get('reason', 'Unknown')}", "ERROR")
        
        return 0 if self.tests_passed == self.tests_run else 1

def main():
    tester = NotchyLimitAPITester()
    return tester.run_all_tests()

if __name__ == "__main__":
    sys.exit(main())
