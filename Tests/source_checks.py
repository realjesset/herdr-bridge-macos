#!/usr/bin/env python3
"""Portable structural checks; NOT a substitute for Swift or macOS runtime tests."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class SourceChecks(unittest.TestCase):
    def test_security_and_lifecycle_guards(self):
        source = (ROOT / 'Sources/HerdrBridge/Bridge.swift').read_text()
        for token in ['ClearAllForwardings=yes', 'StrictHostKeyChecking=yes',
                      'ForwardAgent=no', 'ForwardX11=no', 'GatewayPorts=no',
                      'BatchMode=yes', 'ControlPersist=no', '0o700',
                      '"-F", "/dev/null"', '"-O", operation',
                      'generation == epoch', '>= 15', '.activating',
                      'case .success', '"cancel"', '"exit"', 'forMode: .common']:
            self.assertIn(token, source)
        self.assertNotIn('"-N"', source)
    def test_notification_feedback_and_explicit_retry(self):
        source = (ROOT / 'Sources/HerdrBridge/main.swift').read_text()
        for token in ['getNotificationSettings', 'case .denied:',
                      'case .notDetermined:', 'settings.alertSetting',
                      'refreshNotificationSettings(retryPending: true)',
                      'if case .pending = entry.state', 'Send Test Notification',
                      'Notification error:', 'Permission error:']:
            self.assertIn(token, source)
        retry = source.split('private func refreshNotificationSettings', 1)[1].split('private var alias', 1)[0]
        self.assertNotIn('bridge.approve', retry)
        test = source.split('@objc private func testNotification()', 1)[1].split('@objc private func forward', 1)[0]
        self.assertNotIn('bridge.approve', test)

    def test_package_and_bundle(self):
        self.assertIn('.macOS(.v13)', (ROOT / 'Package.swift').read_text())
        self.assertIn('LSUIElement', (ROOT / 'Info.plist').read_text())
        self.assertIn('codesign', (ROOT / 'build-app.sh').read_text())
if __name__ == '__main__':
    unittest.main()
